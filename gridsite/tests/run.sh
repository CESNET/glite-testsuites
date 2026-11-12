#!/bin/bash
#
# Copyright (c) 2026 CESNET
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ------------------------------------------------------------------------------
# Runs the GridSite test suite. Launched by the tester, not by root.
#
#   tester$  make -C tools                              # own test credentials
#   root#    gridsite/tests/setup.sh -u tester          # Apache, anchors, ACLs
#   tester$  gridsite/tests/run.sh [-t|-c|-x] [-o file] [--dry-run]
#
# The GridSite package under test has to be installed and Apache running with it;
# docs/gridsite.md says what else has to be in place. Everything the tests need to
# know about this deployment comes from $STATE_DIR/gridsite.env.
#
# The tests write their scratch ($$.tmp, the role comparison files) into the
# current directory and drop .gacl files into the document root, so this script
# cd's into its own directory and needs both it and the document root writable -
# setup.sh -u arranges that.
# ------------------------------------------------------------------------------

GSTESTS=$(cd -- "$(dirname -- "$0")" && pwd)
# Sources $GS_ENV (which setup.sh writes), points the process at the test
# credentials and fills in the paths of this deployment.
source "$GSTESTS/gridsite-common.sh"

PROGNAME=$(basename "$0")
DRY_RUN=0
TOTAL=0

showHelp()
{
	cat << EndHelpHeader
Script for running the GridSite integration tests against an Apache serving this
machine over https. The tests drive that server with curl and the gridsite client
commands, so what has to be in place is the package, its configuration and the
credentials.

Prerequisites:
   - test credentials:  make -C tools   (as the tester)
   - testbed configured:  sudo gridsite/tests/setup.sh -u <tester>   (as root),
     which installs the trust anchors, writes the Apache configuration, restarts
     the server and makes the document root writable by both sides
   - the environment variables from $STATE_DIR/gridsite.env, which setup.sh
     writes (GS_ENV=<file> uses a different one)

The ordered list of tests can be printed with --dry-run.

Returned values:
    Exit TEST_OK: No check failed
    Exit TEST_ERROR: At least one check failed
    Exit 2: Wrong input or unusable environment

EndHelpHeader

	echo "Usage: $PROGNAME [OPTIONS]"
	output_usage
	echo "      --dry-run          Print the tests that would run and exit."
}

# Every test of the suite, in the order it has always run: reachability first,
# then the ACL, command and delegation behaviour, then the packaging of the
# package under test. ping-remote.sh used to be handed the host of whoever ran the
# generated script; the tester is on the testbed now, so it gets the name the
# server serves.
gridsite_test_list()
{
	run_test ./ping-remote.sh "$GS_SERVER"
	if [ -n "$GS_HTTPD_CONF" ]; then
		run_test ./ping-local.sh -f "$GS_HTTPD_CONF"
	else
		run_test ./ping-local.sh
	fi
	run_test ./gridsite-test-all.sh
	run_test ./gridsite-test-session-reuse.sh
	run_test ./gridsite-test-putproxy-new.sh
	run_test ./gridsite-test-packaging.sh
	run_test ./gridsite-test-build.sh
}

# One test. Arguments are passed through as words, so paths may contain spaces;
# only the output option is deliberately expanded unquoted, because it is empty
# when the caller let the tests autodetect and there is then no argument at all.
#
# The heading and the output go through tee together so that the saved log reads
# like the console did. It is tee'd per test rather than around the whole list on
# purpose: a pipeline would run gridsite_test_list() in a subshell and the count of
# how many tests ran would be lost with it.
run_test()
{
	local slice verdicts reported rc

	TOTAL=$((TOTAL + 1))

	if [ "$DRY_RUN" -eq 1 ]; then
		printf '%s\n' "$*"
		return 0
	fi

	# Two files, because two things have to be told apart and each answers one of them:
	# what the test printed, kept apart from the heading above it, and what it reported
	# - every status verb leaves its name in the file named by $TEST_VERDICTS, which is
	# the only way to know that a line saying 'done' was there, whether the test printed
	# it plain, in ANSI colours or between <font> tags.
	slice=$(mktemp "${STATE_DIR:-/tmp}/gridsite-slice.XXXXXX")
	verdicts=$(mktemp "${STATE_DIR:-/tmp}/gridsite-verdicts.XXXXXX")

	{
		report_subsection "$*"
		# shellcheck disable=SC2086
		TEST_VERDICTS=$verdicts "$@" $OUTPUT_OPT 2>&1 | tee "$slice"
		rc=${PIPESTATUS[0]}
		# A test that gives up - no credentials, a document root it cannot write, a
		# server that does not answer - prints its reason and comes back without a
		# status verb. Nothing the failure count sees would then mention it, and the
		# report would read as a list of passes with holes in it. A test that reported a
		# failure and came back with TEST_ERROR has accounted for itself already, and is
		# counted once and not twice.
		#
		# This goes into the tee'd output rather than into a counter: this block is a
		# pipeline, and a counter set here would not outlive it.
		reported=0
		[ -s "$verdicts" ] && reported=1
		[ "$($SYS_GREP -c -- '-TEST FAILED-' "$slice" 2> /dev/null)" -gt 0 ] && reported=1
		if [ "$rc" -ne 0 ] && [ "$reported" -eq 0 ]; then
			printf "ABORTED-TEST %s stopped with exit code %d without reporting a verdict.$lf" \
				"$1" "$rc"
		fi
		echo
	} 2>&1 | tee -a "$log"
	$SYS_RM "$slice" "$verdicts"
}

# The preamble shared by what is printed while running and by the saved report.
report_preamble()
{
	report_header "$TITLE"
	report_facts "${1:-}"
	report_section 'Testbed configuration'
	if [ -r "$(state_file "gridsite.setup.$EXT")" ]; then
		report_paragraph "Its own log, including the text of the setup script that ran, is $(state_file "gridsite.setup.$EXT")."
	fi
	report_pre "$envfile"
}

if ! parse_output_args "$@"; then
	printf "Try '%s -h'.\n" "$PROGNAME" >&2
	exit 2
fi
i=0
while [ "$i" -lt "${#ARGS_LEFT[@]}" ]; do
	case "${ARGS_LEFT[$i]}" in
		'--dry-run') DRY_RUN=1 ;;
		*)
			printf "Unknown option '%s'.\n" "${ARGS_LEFT[$i]}" >&2
			printf "Try '%s -h'.\n" "$PROGNAME" >&2
			exit 2
			;;
	esac
	i=$((i + 1))
done

if [ "$WANT_HELP" -eq 1 ]; then
	showHelp
	exit 2
fi

envfile=$GS_ENV_FILE
if [ ! -r "$envfile" ]; then
	if [ "$DRY_RUN" -eq 0 ]; then
		printf 'No testbed configuration in %s.\n\n' "$envfile" >&2
		printf 'Configure the testbed once as root:\n' >&2
		printf '    sudo %s/setup.sh -u %s\n\n' "$GSTESTS" "$(id -un)" >&2
		printf 'or point GS_ENV at a file exporting GS_HTDOCS, GS_PROXYCACHE and friends.\n' >&2
		exit 2
	fi
	# The note goes to stderr so that --dry-run output stays just the list.
	printf 'Note: no testbed configuration in %s; the list is printed regardless.\n' "$envfile" >&2
fi

# Credentials come from tools/ and are never generated here. --dry-run only prints
# the list, so it insists on nothing.
if [ "$DRY_RUN" -eq 0 ]; then
	require_binaries "$GRIDPROXYINFO" "$SYS_CURL"
	require_credentials
fi

if [ "$DRY_RUN" -eq 1 ]; then
	gridsite_test_list
	exit 0
fi

# What the tests are about to do, stated before any of them can fail: it turns
# "everything reported 000" into one sentence about the server not answering.
if ! check_socket "$GS_SERVER" "$GS_PORT"; then
	abort "Nothing is listening on $GS_SERVER:$GS_PORT.

Start the Apache this testbed was configured with, or run
    sudo $GSTESTS/setup.sh -u $(id -un)
again - it writes $GS_HTTPD_CONF and starts the server with it."
fi

if ! touch "$GS_HTDOCS/.writable-$$" 2> /dev/null; then
	abort "$GS_HTDOCS is not writable by $(id -un).

The tests drop .gacl files and a test.cgi into the document root of the server.
As root:
    setfacl -R -m u:$(id -un):rwX -d -m u:$(id -un):rwX $GS_HTDOCS $GS_PROXYCACHE"
fi
rm -f "$GS_HTDOCS/.writable-$$"

cd "$GSTESTS" || abort "Cannot enter the test directory $GSTESTS."

if ! touch ".run-writable.$$" 2> /dev/null; then
	abort "The tests write their scratch files into $(pwd), which $(id -un) cannot write to.
As root, either
    setfacl -R -m u:$(id -un):rwX -d -m u:$(id -un):rwX $TESTSUITE_HOME
or, if you cloned the repository as somebody else,
    chown -R $(id -un) $TESTSUITE_HOME"
fi
rm -f ".run-writable.$$"

if [ ! -w "$STATE_DIR" ]; then
	abort "$STATE_DIR is not writable by $(id -un). Run setup.sh -u $(id -un), or point STATE_DIR at a writable directory."
fi

TITLE="GridSite integration tests on $GS_SERVER"
if [ -n "${is_html:-}" ]; then
	EXT=html
else
	EXT=txt
fi
log=$(state_file gridsite.output.log)
report=$(state_file "gridsite.report.$EXT")
start=$(date +%s)

# The tests go to the console as they run and are captured for the report, which
# is written afterwards from the capture. -o is never passed down to the tests:
# the report is assembled here from what they print.
#
# A function rather than a brace group so that where the output goes can be chosen
# without reopening anything. '> /dev/stdout' would have been the short way of
# sending it to the terminal, but './run.sh -t > file' is a normal way to run a test
# suite and there stdout *is* that file - opening it again truncates it, and the
# report landed over its own header.
emit_console()
{
	{
		report_preamble
		report_section 'Server under test'
		report_fact 'URL' "$GS_URL"
		report_fact 'Apache' "${SYS_APACHE} as ${GS_HTTPD_USER}"
		report_fact 'configuration' "$GS_HTTPD_CONF"
		report_fact 'delegation CGI' "$GS_CGI"
		report_fact 'document root' "$GS_HTDOCS"
		report_fact 'proxy cache' "$GS_PROXYCACHE"
		report_section 'Tests'
		: > "$log"
		gridsite_test_list
		FAILED=$($SYS_GREP -c -- '-TEST FAILED-' "$log")
		[ -n "$FAILED" ] || FAILED=0
		ABORTED=$($SYS_GREP -c -- 'ABORTED-TEST' "$log")
		[ -n "$ABORTED" ] || ABORTED=0
		duration=$(( $(date +%s) - start ))
		report_section 'Summary'
		report_facts "$duration"
		# $FAILED counts printed failures, $ABORTED the scripts that stopped before they
		# could print one, $TOTAL the scripts that were started.
		if [ "$FAILED" -eq 0 ] && [ "$ABORTED" -eq 0 ]; then
			printf "All %d test scripts ran and none printed a failure.$lf" "$TOTAL"
		elif [ "$ABORTED" -gt 0 ]; then
			printf "%d test script(s) stopped before reporting a verdict; %d printed failure(s) across the %d that ran.$lf" \
				"$ABORTED" "$FAILED" "$TOTAL"
		else
			printf "%d printed failure(s) across %d test script(s); the details are above.$lf" "$FAILED" "$TOTAL"
		fi
		report_verdict "$((FAILED + ABORTED))"
		report_paragraph "Raw test output: $log"
		report_tail
	} 2>&1
}

if [ "$OUTPUT_TO_FILE" -eq 1 ]; then
	emit_console > "$OUTPUT_FILE"
else
	emit_console
fi

# The standalone report, for a run whose console went elsewhere.
{
	report_preamble "$duration"
	report_section 'Tests'
	report_raw "$log"
	report_section 'Summary'
	report_facts "$duration"
	report_verdict "$((FAILED + ABORTED))"
	report_tail
} > "$report"

printf 'Report: %s\n' "$report" >&2

if [ "$FAILED" -gt 0 ] || [ "$ABORTED" -gt 0 ]; then
	exit $TEST_ERROR
fi
exit $TEST_OK
