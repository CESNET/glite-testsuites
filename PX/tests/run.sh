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
# Runs the PX (proxy renewal) test suite. Launched by the tester, not by root.
#
#   tester$  make -C tools                       # test credentials
#   root#    PX/tests/setup.sh -u tester         # trust anchors, VOMS trust, checks
#   tester$  PX/tests/run.sh [-t|-c|-x] [-o file] [--dry-run]
#
# The test deposits the tester's proxy with the MyProxy server on this machine,
# waits for the renewal, and compares what came back with what was deposited - so
# the run takes as long as the renewal daemon takes to poll, PX_RENEWAL_WAIT seconds
# of it (half an hour by default). There is no way to shorten that from the tests
# without stopping the thing they measure: the old generated user script waited the
# same time, it just did not say so.
#
# The tests write their $$.tmp scratch into the current directory, so this script
# cd's into its own directory and needs it to be writable - setup.sh -u arranges
# that.
# ------------------------------------------------------------------------------

PXTESTS=$(cd -- "$(dirname -- "$0")" && pwd)
# Sources $PX_ENV (which setup.sh writes) and points the process at the test
# credentials, then derives the server, its DN and the wait from them.
source "$PXTESTS/px-common.sh"

PROGNAME=$(basename "$0")
DRY_RUN=0
TOTAL=0

showHelp()
{
	cat << EndHelpHeader
Script for running the PX proxy-deposit and renewal tests against the MyProxy
server on the testbed. The tests deposit the tester's proxy, wait for the renewal
and compare the two, so they take about half an hour.

Prerequisites:
   - test credentials:  make -C tools   (as the tester)
   - testbed configured:  sudo PX/tests/setup.sh -u <tester>   (as root), which
     installs the trust anchors, the VOMS trust files, and checks the server
   - a MyProxy server running on $PX_SERVER port $PX_PORT and the glite-proxy-renew,
     myproxy-init and myproxy-store commands on \$PATH (docs/px.md)
   - the environment variables from $STATE_DIR/px.env, which setup.sh writes
     (PX_ENV=<file> uses a different one)

The ordered list of tests can be printed with --dry-run, which insists on nothing
and runs nothing.

Returned values:
    Exit TEST_OK: No check failed
    Exit TEST_ERROR: At least one check failed
    Exit 2: Wrong input or unusable environment

EndHelpHeader

	echo "Usage: $PROGNAME [OPTIONS]"
	output_usage
	echo "      --dry-run          Print the tests that would run and exit."
}

# Every test of the suite, in the order the generated user script of old ran them.
px_test_list()
{
	run_test ./px-test-all.sh
	run_test ./px-test-packaging.sh
	run_test ./px-test-build.sh
}

# One test. Arguments are passed through as words, so paths may contain spaces;
# only the output option is deliberately expanded unquoted, because it is empty
# when the caller let the tests autodetect and there is then no argument at all.
#
# The heading and the output go through tee together so that the saved log reads
# like the console did. It is tee'd per test rather than around the whole list on
# purpose: a pipeline would run px_test_list() in a subshell and the count of how
# many tests ran would be lost with it.
run_test()
{
	local slice rc verdicts

	TOTAL=$((TOTAL + 1))

	if [ "$DRY_RUN" -eq 1 ]; then
		printf '%s\n' "$*"
		return 0
	fi

	# What the test itself printed, kept apart from the heading above it so that the
	# line below can tell whether it reported a verdict at all.
	slice=$(mktemp "${STATE_DIR:-/tmp}/px-slice.XXXXXX")

	{
		report_subsection "$*"
		# shellcheck disable=SC2086
		"$@" $OUTPUT_OPT 2>&1 | tee "$slice"
		rc=${PIPESTATUS[0]}
		# A test that gives up - no credentials, a myproxy-server that does not answer,
		# a certificate it cannot read - prints its reason and comes back without a
		# status verb. Nothing the failure count sees would then mention it, and the
		# report would read as a list of passes with holes in it. A test that did print
		# a verb and came back with TEST_ERROR has reported itself, and is counted once
		# and not twice.
		#
		# This goes into the tee'd output rather than into a counter: this block is a
		# pipeline, and a counter set here would not outlive it.
		verdicts=$($SYS_GREP -c -E -- '-TEST (FAILED|DONE|SKIPPED|WARNING|MISSED)-' "$slice" 2> /dev/null)
		[ -n "$verdicts" ] || verdicts=0
		if [ "$rc" -ne 0 ] && [ "$verdicts" -eq 0 ]; then
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
	if [ -r "$(state_file "px.setup.$EXT")" ]; then
		report_paragraph "Its own log, including the text of the setup script that ran, is $(state_file "px.setup.$EXT")."
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

envfile=$PX_ENV_FILE
if [ ! -r "$envfile" ]; then
	if [ "$DRY_RUN" -eq 0 ]; then
		printf 'No testbed configuration in %s.\n\n' "$envfile" >&2
		printf 'Configure the testbed once as root:\n' >&2
		printf '    sudo %s/setup.sh -u %s\n\n' "$PXTESTS" "$(id -un)" >&2
		printf 'or point PX_ENV at a file exporting PX_SERVER and MYPROXY_SERVER_DN.\n' >&2
		exit 2
	fi
	# The note goes to stderr so that --dry-run output stays just the list.
	printf 'Note: no testbed configuration in %s; the list is printed regardless.\n' "$envfile" >&2
fi

# Credentials come from tools/ and are never generated here: a test that invented
# its own credentials could not tell an authorised testbed from an unconfigured one
# - which is exactly the difference px-test-all.sh is built to measure.
if [ "$DRY_RUN" -eq 0 ]; then
	require_binaries "$GRIDPROXYINFO" glite-proxy-renew myproxy-init myproxy-store
	require_credentials

	# The one thing every check in the suite needs and nothing else will say a plain
	# reason about: myproxy answers with a store connection error, which reads like a
	# bug in the client.
	if ! check_socket "$PX_SERVER" "$PX_PORT"; then
		abort "Nothing is answering on $PX_SERVER:$PX_PORT.

Start the MyProxy server (systemctl start myproxy-server), or point PX_SERVER and
PX_PORT at the machine that serves. setup.sh -u $(id -un) says what else it checked."
	fi
	if [ -z "$MYPROXY_SERVER_DN" ]; then
		printf 'Note: MYPROXY_SERVER_DN is empty; myproxy will refuse the connection unless\n' >&2
		printf 'the server is the one this machine serves and its certificate is readable.\n' >&2
	fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
	px_test_list
	exit 0
fi

cd "$PXTESTS" || abort "Cannot enter the test directory $PXTESTS."

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

HNAME=$(hostname -f 2> /dev/null || hostname)
TITLE="PX integration tests on $HNAME"
if [ -n "${is_html:-}" ]; then
	EXT=html
else
	EXT=txt
fi
log=$(state_file px.output.log)
report=$(state_file "px.report.$EXT")
start=$(date +%s)

printf 'px-test-all.sh will now wait %ss for the renewal; the run is not stuck.\n' "$PX_RENEWAL_WAIT" >&2

# The tests go to the console as they run and are captured for the report, which is
# written afterwards from the capture. -o is never passed down to the tests: the
# report is assembled here from what they print.
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
		report_section 'Service under test'
		report_fact 'MyProxy server' "$PX_SERVER:$PX_PORT"
		report_fact 'server DN' "$MYPROXY_SERVER_DN"
		report_fact 'VO' "$PX_VO"
		report_fact 'host certificate' "$MYPROXY_HOST_CERT"
		report_fact 'proxy lifetime' "${PX_PROXY_HOURS} h"
		report_fact 'renewal wait' "${PX_RENEWAL_WAIT} s"
		report_section 'Tests'
		: > "$log"
		px_test_list
		FAILED=$($SYS_GREP -c -- '-TEST FAILED-' "$log")
		[ -n "$FAILED" ] || FAILED=0
		ABORTED=$($SYS_GREP -c -- 'ABORTED-TEST' "$log")
		[ -n "$ABORTED" ] || ABORTED=0
		duration=$(( $(date +%s) - start ))
		report_section 'Summary'
		report_facts "$duration"
		# $FAILED counts printed failures, $ABORTED the scripts that stopped before they
		# could print one, $TOTAL the scripts that were started. The three are stated
		# separately rather than in one sentence about "checks".
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
