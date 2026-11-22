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
# Runs the CANL-C test suite. Launched by the tester, not by root.
#
#   tester$  make -C tools                                  # test credentials
#   tester$  make -C CANL-C/tests top_srcdir=~/canl-c       # the two samples
#   root#    CANL-C/tests/setup.sh -u tester                # trust anchors
#   tester$  CANL-C/tests/run.sh [-t|-c|-x] [-o file] [--dry-run]
#
# There is no service to reach: every test starts a server on a free port of this
# machine and connects to it, so the things that have to be right are the trust
# anchors of the test CA and the programs the tests drive. canl-test-cert-handle.sh
# runs first, as it always has - it hands its own proxy to the default location,
# which is why it must not come after the tests that read that proxy.
#
# The tests write their $$.err scratch into the current directory, so this script
# cd's into its own directory and needs it to be writable - setup.sh -u arranges
# that.
# ------------------------------------------------------------------------------

CANLTESTS=$(cd -- "$(dirname -- "$0")" && pwd)
# Sources $CANL_ENV (which setup.sh writes) and points the process at the test
# credentials, then derives the certificate paths from them.
source "$CANLTESTS/canl-common.sh"

PROGNAME=$(basename "$0")
DRY_RUN=0
TOTAL=0

showHelp()
{
	cat << EndHelpHeader
Script for running the CANL-C integration tests. The tests start a CANL server on
a free port here and connect to it, so nothing has to be deployed anywhere.

Prerequisites:
   - test credentials:  make -C tools   (as the tester)
   - testbed configured:  sudo CANL-C/tests/setup.sh -u <tester>   (as root),
     which installs the trust anchors of that CA into /etc/grid-security
   - the CANL-C package under test installed, providing emi-canl-proxy-init and
     emi-canl-delegation
   - the two sample programs, built by the Makefile next to this script:
     make -C CANL-C/tests top_srcdir=<CANL-C source tree>
   - the environment variables from $STATE_DIR/canl.env, which setup.sh writes
     (CANL_ENV=<file> uses a different one)

The ordered list of tests can be printed with --dry-run. canl-test-ocsp.sh is not
in it, and docs/canl-c.md says why.

Returned values:
    Exit TEST_OK: No check failed
    Exit TEST_ERROR: At least one check failed
    Exit 2: Wrong input or unusable environment

EndHelpHeader

	echo "Usage: $PROGNAME [OPTIONS]"
	output_usage
	echo "      --dry-run          Print the tests that would run and exit."
}

# Where one of the programs is: a build sitting next to these scripts - what the
# Makefile here produces - is preferred over the name on $PATH, because a tester
# who has just built it means that one. Relative on purpose, run.sh cd's here.
canl_bin()
{
	if [ -x "$CANLTESTS/$1" ]; then
		printf './%s' "$1"
	else
		printf '%s' "$1"
	fi
}

# Every test of the suite, in the order it has always run. The paths are passed
# explicitly so that a build next to the scripts is used even when an older copy
# of the same name is installed on $PATH.
canl_test_list()
{
	run_test ./canl-test-cert-handle.sh --origin "$X509_USER_CERT" --key "$X509_USER_KEY" \
		-i "$PROXY_INIT_BIN" -d "$DELEGATION_BIN"
	run_test ./canl-test-cs-openssl.sh -s "$SERVER_BIN" -k "$CLIENT_BIN"
	run_test ./canl-test-sec-connection.sh -s "$SERVER_BIN" -k "$CLIENT_BIN"
	run_test ./canl-test-sha2.sh -s "$SERVER_BIN" -k "$CLIENT_BIN"
	run_test ./canl-test-build.sh
}

# One test. Arguments are passed through as words, so paths may contain spaces;
# only the output option is deliberately expanded unquoted, because it is empty
# when the caller let the tests autodetect and there is then no argument at all.
#
# The heading and the output go through tee together so that the saved log reads
# like the console did. It is tee'd per test rather than around the whole list on
# purpose: a pipeline would run canl_test_list() in a subshell and the count of how
# many tests ran would be lost with it.
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
	slice=$(mktemp "${STATE_DIR:-/tmp}/canl-slice.XXXXXX")
	verdicts=$(mktemp "${STATE_DIR:-/tmp}/canl-verdicts.XXXXXX")

	{
		report_subsection "$*"
		# shellcheck disable=SC2086
		TEST_VERDICTS=$verdicts "$@" $OUTPUT_OPT 2>&1 | tee "$slice"
		rc=${PIPESTATUS[0]}
		# A test that gives up - no credentials, a directory it cannot write, a service
		# that does not answer - prints its reason and comes back without a status verb.
		# Nothing the failure count sees would then mention it, and the report would read
		# as a list of passes with holes in it. A test that reported a failure and came
		# back with TEST_ERROR has accounted for itself already, and is counted once and
		# not twice.
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
	if [ -r "$(state_file "canl.setup.$EXT")" ]; then
		report_paragraph "Its own log, including the text of the setup script that ran, is $(state_file "canl.setup.$EXT")."
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

envfile=$CANL_ENV_FILE
if [ ! -r "$envfile" ]; then
	if [ "$DRY_RUN" -eq 0 ]; then
		printf 'No testbed configuration in %s.\n\n' "$envfile" >&2
		printf 'Configure the testbed once as root:\n' >&2
		printf '    sudo %s/setup.sh -u %s\n\n' "$CANLTESTS" "$(id -un)" >&2
		printf 'or point CANL_ENV at a file exporting TEST_CERTS and the CANL_* paths.\n' >&2
		exit 2
	fi
	# The note goes to stderr so that --dry-run output stays just the list.
	printf 'Note: no testbed configuration in %s; the list is printed regardless.\n' "$envfile" >&2
fi

# Credentials come from tools/ and are never generated here: a test that invented
# its own credentials could not tell an authorised testbed from an unconfigured
# one. --dry-run only prints the list, so it insists on nothing.
if [ "$DRY_RUN" -eq 0 ]; then
	require_binaries "$GRIDPROXYINFO"
	require_credentials
fi

SERVER_BIN=$(canl_bin "$EMI_CANL_SERVER")
CLIENT_BIN=$(canl_bin "$EMI_CANL_CLIENT")
PROXY_INIT_BIN=$(canl_bin "$EMI_CANL_PROXY_INIT")
DELEGATION_BIN=$(canl_bin "$EMI_CANL_DELEGATION")

if [ "$DRY_RUN" -eq 1 ]; then
	canl_test_list
	exit 0
fi

missing=''
for bin in "$SERVER_BIN" "$CLIENT_BIN" "$PROXY_INIT_BIN" "$DELEGATION_BIN"; do
	check_exec "$bin" || missing="${missing} ${bin}"
done
if [ -n "$missing" ]; then
	printf 'Cannot start without:%s\n\n' "$missing" >&2
	printf 'emi-canl-proxy-init and emi-canl-delegation come with the CANL-C package\n' >&2
	printf 'under test. The two samples come from its source tree:\n\n' >&2
	printf '    make -C %s top_srcdir=<CANL-C source tree>\n\n' "$CANLTESTS" >&2
	printf 'Or point EMI_CANL_SERVER, EMI_CANL_CLIENT, EMI_CANL_PROXY_INIT and\n' >&2
	printf 'EMI_CANL_DELEGATION at built copies.\n' >&2
	exit 2
fi

cd "$CANLTESTS" || abort "Cannot enter the test directory $CANLTESTS."

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
TITLE="CANL-C integration tests on $HNAME"
if [ -n "${is_html:-}" ]; then
	EXT=html
else
	EXT=txt
fi
log=$(state_file canl.output.log)
report=$(state_file "canl.report.$EXT")
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
		report_section 'Programs under test'
		report_fact 'server' "$SERVER_BIN"
		report_fact 'client' "$CLIENT_BIN"
		report_fact 'proxy-init' "$PROXY_INIT_BIN"
		report_fact 'delegation' "$DELEGATION_BIN"
		report_fact 'host certificate' "$CANL_HOST_CERT"
		report_section 'Tests'
		: > "$log"
		canl_test_list
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
