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
# Runs the rOCCI test suite. Launched by the tester, not by root.
#
#   root#    rOCCI/tests/setup.sh -u tester    # anchors, sudo rule, environment
#   tester$  rOCCI/tests/run.sh [-t|-c|-x] [-o file] [--dry-run]
#
# rOCCI is tested by putting the server on a backend and asking it what it is: each
# round switches the backend through the program setup.sh installed, and then runs
# the deployment test against the server that has just been reconfigured. The
# backends and how long each may take to appear are in ROCCI_BACKENDS.
#
# A backend that this testbed simply does not have - no service discovery, or nothing
# of that kind registered in it - is reported as skipped and does not fail the run. A
# switch that fails for any other reason is a failure, and the deployment test that
# would have been meaningless after it is not run.
#
# The tests write their $$.tmp scratch into the current directory, so this script
# cd's into its own directory and needs it writable - setup.sh -u arranges that.
# ------------------------------------------------------------------------------

ROCITESTS=$(cd -- "$(dirname -- "$0")" && pwd)
# Sources $ROCCI_ENV (which setup.sh writes) and fills in the server, the port, the
# helper the backend switch goes through and the list of backends.
source "$ROCITESTS/rOCCI-common.sh"

PROGNAME=$(basename "$0")
DRY_RUN=0
TOTAL=0

showHelp()
{
	cat << EndHelpHeader
Script for running the rOCCI integration tests against the rOCCI server of this
machine. Every round selects a backend and then asks the server what it serves, so
what has to be in place is the server, its configuration and the right to switch it.

Prerequisites:
   - testbed configured:  sudo rOCCI/tests/setup.sh -u <tester>   (as root), which
     installs the trust anchors, installs the backend switch and names it in sudoers,
     and writes the Apache configuration's location into the environment
   - the rOCCI server serving https on $ROCCI_SERVER:$ROCCI_PORT
   - the rOCCI command line client and curl
   - the environment variables from $STATE_DIR/rocci.env, which setup.sh writes
     (ROCCI_ENV=<file> uses a different one)

The backends a run goes through are $ROCCI_BACKENDS - name:SECONDS-TO-WAIT, with
'dummy' needing no waiting at all. Override the whole list with ROCCI_BACKENDS when
this testbed has other backends or fewer.

The ordered list of what would run can be printed with --dry-run.

Returned values:
    Exit TEST_OK: No check failed
    Exit TEST_ERROR: At least one check failed
    Exit 2: Wrong input or unusable environment

EndHelpHeader

	echo "Usage: $PROGNAME [OPTIONS]"
	output_usage
	echo "      --dry-run          Print what would run and exit."
}

# One switch, and the deployment test that goes with it. The switch is reported as
# its own subsection because that is where most of the waiting happens and where a
# missing backend shows up; the test itself is counted like a test everywhere else in
# this repository is.
#
# The output goes through tee so that the saved log reads like the console did. It is
# tee'd per step rather than around the whole list on purpose: a pipeline would run
# rocci_test_list() in a subshell and the count of how many tests ran would be lost
# with it.
run_round()
{
	local backend=$1
	local waiting=$2
	local rc=0 out='' line

	if [ "$DRY_RUN" -eq 1 ]; then
		printf 'sudo -n %s %s %s\n' "$ROCCI_TOGGLE" "$backend" "$waiting"
		printf './rOCCI-test-deployment.sh\n'
		return 0
	fi

	# The switch happens outside the tee'd block below, so that its exit code is
	# still here afterwards: inside a pipeline this would all run in a subshell and
	# the decision whether the deployment test has anything to test would be lost.
	#
	# The helper prints what it selected and where it wrote the credentials; it never
	# prints a password. Its exit code decides the next step - 3 means this testbed
	# has no such backend, which is not a failure of the server.
	out=$(rocci_switch "$backend" "$waiting" 2>&1); rc=$?

	{
		report_subsection "Switching the server to the $backend backend"
		printf '%s\n' "$out" | while read -r line; do
			[ -n "$line" ] && printf '%s\n' "$line"
		done
		# $lf belongs in the format string, where it is a newline in text mode and a
		# <br> in HTML; as an argument it would print as the two characters \n.
		case "$rc" in
			0) printf "The server runs on %s; the deployment test follows.$lf" "$backend" ;;
			3)
				printf "SKIPPED-TEST %s is not available on this testbed, so its deployment test was not run.$lf" \
					"$backend"
				report_note "run.sh continues with the remaining backends"
			;;
			*)
				printf "ABORTED-TEST switching to %s stopped with exit code %d, so its deployment test was not run.$lf" \
					"$backend" "$rc"
			;;
		esac
		echo
	} 2>&1 | tee -a "$log"

	if [ "$rc" -eq 0 ]; then
		run_test ./rOCCI-test-deployment.sh
	fi
	return 0
}

# One test, in the shape every other suite's driver uses it. -o is never passed down:
# the report is assembled here from what the test prints.
run_test()
{
	local slice verdicts reported rc

	TOTAL=$((TOTAL + 1))

	# Two files, because two things have to be told apart and each answers one of them:
	# what the test printed, kept apart from the heading above it, and what it reported
	# - every status verb leaves its name in the file named by $TEST_VERDICTS, which is
	# the only way to know that a line saying 'done' was there, whether the test printed
	# it plain, in ANSI colours or between <font> tags.
	slice=$(mktemp "${STATE_DIR:-/tmp}/rocci-slice.XXXXXX")
	verdicts=$(mktemp "${STATE_DIR:-/tmp}/rocci-verdicts.XXXXXX")

	{
		report_subsection "$*"
		# shellcheck disable=SC2086
		TEST_VERDICTS=$verdicts "$@" $OUTPUT_OPT 2>&1 | tee "$slice"
		rc=${PIPESTATUS[0]}
		# A test that gives up - no credentials for the backend, a directory it cannot
		# write - prints its reason and comes back without a status verb. Nothing the
		# failure count sees would then mention it, and the report would read as a list
		# of passes with holes in it. A test that reported a failure and came back with
		# TEST_ERROR has accounted for itself already, and is counted once and not twice.
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

# Every round, in the order the suite has always gone through them: whatever the
# server was left on, then each backend the service discovery can provide.
rocci_test_list()
{
	local spec backend waiting

	for spec in $ROCCI_BACKENDS; do
		backend=${spec%%:*}
		waiting=${spec#*:}
		if [ "$waiting" = "$spec" ]; then
			waiting=1800
		fi
		run_round "$backend" "$waiting"
	done
}

# The preamble shared by what is printed while running and by the saved report.
# The environment file is included; the credentials file is not, and must not be -
# it holds the password of the backend that was selected last.
report_preamble()
{
	report_header "$TITLE"
	report_facts "${1:-}"
	report_section 'Testbed configuration'
	if [ -r "$(state_file "rocci.setup.$EXT")" ]; then
		report_paragraph "Its own log, including the text of the setup script that ran, is $(state_file "rocci.setup.$EXT")."
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

envfile=$ROCCI_ENV_FILE
if [ ! -r "$envfile" ]; then
	if [ "$DRY_RUN" -eq 0 ]; then
		printf 'No testbed configuration in %s.\n\n' "$envfile" >&2
		printf 'Configure the testbed once as root:\n' >&2
		printf '    sudo %s/setup.sh -u %s\n\n' "$ROCITESTS" "$(id -un)" >&2
		printf 'or point ROCCI_ENV at a file exporting ROCCI_SERVER, ROCCI_PORT and ROCCI_TOGGLE.\n' >&2
		exit 2
	fi
	# The note goes to stderr so that --dry-run output stays just the list.
	printf 'Note: no testbed configuration in %s; the list is printed regardless.\n' "$envfile" >&2
fi

if [ "$DRY_RUN" -eq 0 ]; then
	require_binaries "$OCCI_CLIENT" "$SYS_CURL"
fi

if [ "$DRY_RUN" -eq 1 ]; then
	rocci_test_list
	exit 0
fi

# Switching backends is the one thing here a tester cannot do without help, and
# without it the run would be one long list of backends it could not select. Asking
# the helper for its usage is how this is checked: it runs as root, prints its help
# and comes back with 2, and nothing on the machine is changed.
if [ ! -x "$ROCCI_TOGGLE" ]; then
	abort "$ROCCI_TOGGLE is not installed.

Switching the rOCCI backend rewrites the Apache configuration the server is served
from and restarts it, which needs root. setup.sh installs the one program the tests
ask for and names it in sudoers:
    sudo $ROCITESTS/setup.sh -u $(id -un)"
fi
# What comes back is the helper's own usage text and exit code 2, which is how it
# answers -h. Anything else is sudo refusing: it says 'a password is required' and
# comes back with 1, and the run would otherwise spend twenty minutes discovering the
# same thing one backend at a time.
switch_probe=$(sudo -n "$ROCCI_TOGGLE" -h 2>&1); switch_rc=$?
if [ "$switch_rc" -ne 2 ]; then
	abort "sudo cannot run $ROCCI_TOGGLE as $(id -un) (it answered with exit code $switch_rc):
${switch_probe}

setup.sh installs a rule for it in /etc/sudoers.d/rocci-test; check that file, or add
the line it prints there by hand:
    $(id -un)	ALL=NOPASSWD: $ROCCI_TOGGLE"
fi

# What the tests are about to do, stated before any of them can fail: it turns
# "everything answered 000" into one sentence about the server not answering.
if ! check_socket "$ROCCI_SERVER" "$ROCCI_PORT"; then
	abort "Nothing is listening on $ROCCI_SERVER:$ROCCI_PORT.

The rOCCI server is served by Apache - start it${ROCCI_SERVICE:+ ($ROCCI_SERVICE)}, or run
    sudo $ROCITESTS/setup.sh -u $(id -un)
again; its report says which configuration it found."
fi

cd "$ROCITESTS" || abort "Cannot enter the test directory $ROCITESTS."

if ! touch ".run-writable.$$" 2> /dev/null; then
	abort "The tests write their scratch files into $(pwd), which $(id -un) cannot write to.
As root, either
    setfacl -R -m u:$(id -un):rwX -d -m u:$(id -un):rwX $TESTSUITE_HOME
or, if you cloned the repository as somebody else,
    chown -R $(id -un) $TESTSUITE_HOME"
fi
rm -f ".run-writable.$$"

# The reply of every request and the credentials of the current backend both land
# here, so it has to be writable and it must not be readable by anybody else who
# happens to have an account on this machine.
if [ ! -w "$STATE_DIR" ]; then
	abort "$STATE_DIR is not writable by $(id -un). Run setup.sh -u $(id -un), or point STATE_DIR at a writable directory."
fi

TITLE="rOCCI integration tests on $ROCCI_SERVER"
if [ -n "${is_html:-}" ]; then
	EXT=html
else
	EXT=txt
fi
log=$(state_file rocci.output.log)
report=$(state_file "rocci.report.$EXT")
start=$(date +%s)

# The tests go to the console as they run and are captured for the report, which is
# written afterwards from the capture.
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
		report_fact 'URL' "$ROCCI_URL"
		report_fact 'configuration' "${ROCCI_CONFIG-not found by setup.sh}"
		report_fact 'service' "${ROCCI_SERVICE:-not found by setup.sh}"
		report_fact 'backend switch' "$ROCCI_TOGGLE"
		report_fact 'backends' "$ROCCI_BACKENDS"
		report_section 'Tests'
		: > "$log"
		rocci_test_list
		FAILED=$($SYS_GREP -c -- '-TEST FAILED-' "$log")
		[ -n "$FAILED" ] || FAILED=0
		ABORTED=$($SYS_GREP -c -- 'ABORTED-TEST' "$log")
		[ -n "$ABORTED" ] || ABORTED=0
		SKIPPED=$($SYS_GREP -c -- 'SKIPPED-TEST' "$log")
		[ -n "$SKIPPED" ] || SKIPPED=0
		duration=$(( $(date +%s) - start ))
		report_section 'Summary'
		report_facts "$duration"
		# $FAILED counts printed failures, $ABORTED the steps that stopped before they
		# could print one, $SKIPPED the backends this testbed does not have and whose
		# tests were therefore not run, $TOTAL the tests that were started. The skipped
		# ones are named because a run of 'dummy' only is not a test of the clouds.
		if [ "$FAILED" -eq 0 ] && [ "$ABORTED" -eq 0 ]; then
			printf "All %d test script(s) ran and none printed a failure." "$TOTAL"
			if [ "$SKIPPED" -gt 0 ]; then
				printf " %d backend(s) are not available on this testbed and their tests were not run.$lf" "$SKIPPED"
			else
				printf "$lf"
			fi
		elif [ "$ABORTED" -gt 0 ]; then
			printf "%d step(s) stopped before reporting a verdict, %d backend(s) were not available, and %d printed failure(s) across the %d test(s) that ran.$lf" \
				"$ABORTED" "$SKIPPED" "$FAILED" "$TOTAL"
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
