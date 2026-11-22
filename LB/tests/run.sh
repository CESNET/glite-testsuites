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
# Runs the LB test suite. Launched by the tester, not by root.
#
#   tester$  make -C tools                    # own test credentials
#   root#    LB/tests/setup.sh -u tester      # trust anchors + testbed config
#   tester$  LB/tests/run.sh [-t|-c|-x] [-o file] [--dry-run]
#
# run.sh needs an LB server already deployed and configured; docs/lb.md lists
# what must be running and which environment the testbed was configured with.
#
# The list in lb_test_list() below is the definition of "the suite" - it is the
# order the generated arrange_lb_test_user.sh used to run. Tests that are not in
# it are listed in docs/lb.md together with what each one needs.
#
# The tests write their scratch files ($$.err, $$_notifications.txt,
# cms-*.json) into the current directory and two of them call helpers that live
# next to them (./JSON_checker, ./cms-split.pl), so this script cd's into its own
# directory and needs it to be writable - setup.sh -u arranges that.
# ------------------------------------------------------------------------------

LBTESTS=$(cd -- "$(dirname -- "$0")" && pwd)
source "$LBTESTS/lb-common.sh"

PROGNAME=$(basename "$0")
DRY_RUN=0
TOTAL=0
FAILED=0

showHelp()
{
	cat << EndHelpHeader
Script for running the LB integration tests against a deployed Logging & Booking
service.

Prerequisites:
   - LB server, logger and interlogger running and accepting this proxy
   - test credentials:  make -C tools   (as the tester)
   - testbed configured:  sudo LB/tests/setup.sh -u <tester>   (as root)
   - environment variables from $STATE_DIR/lb.env, which setup.sh writes
     (LB_ENV=<file> uses a different one)

The full ordered list of tests can be printed with --dry-run. Tests left out of
it, and why, are documented in docs/lb.md.

Returned values:
    Exit TEST_OK: No check failed
    Exit TEST_ERROR: At least one check failed
    Exit 2: Wrong input or unusable environment

EndHelpHeader

	echo "Usage: $PROGNAME [OPTIONS]"
	output_usage
	echo "      --dry-run          Print the tests that would run and exit."
}

# Every test of the suite, in the order it has always run. $log_fprefix is the
# local logger's file, which the two tests that read it take as an argument.
lb_test_list()
{
	run_test ./lb-test-permissions.sh
	run_test ./lb-test-event-delivery.sh
	run_test ./lb-test-il-recovery.sh -f "$log_fprefix"
	run_test ./lb-test-job-registration.sh
	run_test ./lb-test-https.sh
	run_test ./lb-test-job-states.sh
	run_test ./lb-test-logevent.sh "$log_fprefix"
	run_test ./lb-test-collections.sh
	run_test ./lb-test-notif-recovery.sh
	run_test ./lb-test-notif-msg.sh
	run_test ./lb-test-notif.sh
	run_test ./lb-test-notif-switch.sh
	run_test ./lb-test-notif-stream.sh
	run_test ./lb-test-notif-keeper.sh
	run_test ./lb-test-proxy-delivery.sh
	run_test ./lb-test-ws.sh
	run_test ./lb-test-bdii.sh
	run_test ./lb-test-sandbox-transfer.sh
	run_test ./lb-test-changeacl.sh
	run_test ./lb-test-statistics.sh
	run_test ./lb-test-threaded.sh
	run_test ./lb-test-harvester.sh
	run_test ./lb-test-nagios-probe.sh
	run_test ./lb-test-dump-load.sh
	run_test ./lb-test-cream.sh
	run_test perl ./lb-test-purge.pl --i-want-to-purge "$LB_SERVER"
	run_test ./lb-test-build.sh
}

# One test. Arguments are passed through as words, so paths may contain spaces;
# only the output option is deliberately expanded unquoted, because it is empty
# when the caller let the tests autodetect and there is then no argument at all.
#
# The heading and the output go through tee together so that the saved log reads
# like the console did. It is tee'd per test rather than around the whole list on
# purpose: a pipeline would run lb_test_list() in a subshell and the count of how
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
	slice=$(mktemp "${STATE_DIR:-/tmp}/lb-slice.XXXXXX")
	verdicts=$(mktemp "${STATE_DIR:-/tmp}/lb-verdicts.XXXXXX")

	{
		report_subsection "$*"
		# shellcheck disable=SC2086
		TEST_VERDICTS=$verdicts "$@" $OUTPUT_OPT 2>&1 | tee "$slice"
		rc=${PIPESTATUS[0]}
		# A test that gives up - no credentials, a service that does not answer, a file
		# it cannot write - prints its reason and comes back without a status verb.
		# Nothing the failure count sees would then mention it, and the report would read
		# as a list of passes with holes in it. A test that reported a failure and came
		# back with TEST_ERROR has accounted for itself already, and is counted once and
		# not twice; lb-test-purge.pl prints its marker instead of sourcing the library,
		# so a printed one counts as a report as well.
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
	if [ -r "$(state_file "lb.setup.$EXT")" ]; then
		report_paragraph "Its own log, including the text of the setup script that ran, is $(state_file "lb.setup.$EXT")."
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

# Credentials come from tools/ and are never generated here: a test that
# invented its own credentials could not tell an authorised testbed from an
# unconfigured one. --dry-run only prints the list, so it insists on nothing.
credentials_env
if [ "$DRY_RUN" -eq 1 ]; then
	# The note goes to stderr so that --dry-run output stays just the list.
	check_credentials > /dev/null 2>&1 \
		|| printf 'Note: no usable credentials; the list is printed regardless.\n' >&2
else
	require_binaries "$GRIDPROXYINFO"
	require_credentials
fi

# What setup.sh learned about this deployment. LB_ENV is the escape hatch for a
# tester who prefers to name the variables themself.
envfile=${LB_ENV:-$(state_file lb.env)}
if [ -r "$envfile" ]; then
	# shellcheck source=/dev/null
	source "$envfile"
elif [ "$DRY_RUN" -eq 0 ]; then
	printf 'No testbed configuration in %s.\n\n' "$envfile" >&2
	printf 'Configure the testbed once as root:\n' >&2
	printf '    sudo %s/setup.sh -u %s\n\n' "$LBTESTS" "$(id -un)" >&2
	printf 'or point LB_ENV at a file that exports GLITE_WMS_QUERY_SERVER and friends.\n' >&2
	exit 2
fi

# The two files that used to be computed inside the generated user script.
HNAME=${HNAME:-$(hostname -f)}
if [ -z "${log_fprefix:-}" ]; then
	log_fprefix=/var/spool/glite/lb-locallogger
	if [ ! -d "$log_fprefix" ]; then
		log_fprefix=/var/glite/log
	fi
	log_fprefix=$log_fprefix/dglogd.log
fi
LB_SERVER=${GLITE_WMS_QUERY_SERVER:-$HNAME:$GLITE_LB_SERVER_PORT}
export HNAME log_fprefix

if [ "$DRY_RUN" -eq 1 ]; then
	lb_test_list
	exit 0
fi

cd "$LBTESTS" || abort "Cannot enter the test directory $LBTESTS."

if ! touch ".run-writable.$$" 2> /dev/null; then
	abort "The tests write their scratch files into $(pwd), which $(id -un) cannot write to.
As root, either
    setfacl -R -m u:$(id -un):rwX -d -m u:$(id -un):rwX $TESTSUITE_HOME
or, if you cloned the repository as somebody else,
    chown -R $(id -un) $TESTSUITE_HOME"
fi
rm -f ".run-writable.$$"

# testSocket falls back to nc, but JSON_checker has no fallback.
if [ ! -x ./testSocket ] || [ ! -x ./JSON_checker ]; then
	printf "Building the test helpers in $PWD$lf"
	if ! check_exec make; then
		printf "'make' is missing - see docs/requirements.md.$lf"
	elif ! make; then
		printf "Building failed; the tests that need ./testSocket or ./JSON_checker will say so.$lf"
	fi
fi

if [ ! -w "$STATE_DIR" ]; then
	abort "$STATE_DIR is not writable by $(id -un). Run setup.sh -u $(id -un), or point STATE_DIR at a writable directory."
fi

TITLE="LB integration tests on $HNAME"
if [ -n "${is_html:-}" ]; then
	EXT=html
else
	EXT=txt
fi
log=$(state_file lb.output.log)
report=$(state_file "lb.report.$EXT")
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
		report_section 'Tests'
		: > "$log"
		lb_test_list
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
