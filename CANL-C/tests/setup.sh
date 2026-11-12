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
# Prepares a testbed for the CANL-C tests and records what it did. Run as root.
#
#   tester$  make -C tools                                  # test credentials
#   tester$  make -C CANL-C/tests top_srcdir=~/canl-c       # the two samples
#   root#    CANL-C/tests/setup.sh -u tester [-t|-c|-x] [-o file]
#   tester$  CANL-C/tests/run.sh
#
# CANL-C needs no service of its own: every test here starts a CANL server and
# client on this machine and has them talk to each other. What the testbed needs
# is the trust anchors of the test CA, so that is all this installs. It installs
# no packages (docs/requirements.md lists them) and deploys nothing.
#
# TEST_CERTS and STATE_DIR are taken from the environment; export them before
# sudo when the tester generated the credentials somewhere else than /tmp/certs.
#
# Everything is written to $STATE_DIR/canl.setup.txt (or .html with -x),
# including the text of this script, because afterwards that is the only record
# of what the testbed was told.
# ------------------------------------------------------------------------------

CANLTESTS=$(cd -- "$(dirname -- "$0")" && pwd)
source "$CANLTESTS/canl-common.sh"

PROGNAME=$(basename "$0")
TESTER=${SUDO_USER:-}

showHelp()
{
	cat << EndHelpHeader
Script for preparing a testbed for the CANL-C integration tests. Run it as root
once per testbed; the tests themselves run unprivileged via run.sh.

Prerequisites:
   - the tester has generated their test credentials:  make -C tools
   - the four CANL example programs the tests drive, built from a CANL-C source
     tree by the Makefile next to this script (it warns below if they are absent)
   - the packages the tests shell out to (docs/requirements.md)

What it changes:
   - /etc/grid-security/{certificates,vomsdir,hostcert.pem,hostkey.pem}
   - access control lists on this checkout
   - $STATE_DIR/canl.env and the setup report

Unlike the other suites this one installs no packages and starts no service: the
CANL tests run a server and a client against each other on this machine.

Returned values:
    Exit TEST_OK: The testbed is ready
    Exit TEST_ERROR: Something could not be configured, the report says what
    Exit 2: Wrong input

EndHelpHeader

	echo "Usage: sudo $PROGNAME -u TESTER [OPTIONS]"
	output_usage
	echo " -u | --user 'name'     Who will run the tests (default: \$SUDO_USER)."
}

if ! parse_output_args "$@"; then
	printf "Try '%s -h'.\n" "$PROGNAME" >&2
	exit 2
fi
i=0
while [ "$i" -lt "${#ARGS_LEFT[@]}" ]; do
	case "${ARGS_LEFT[$i]}" in
		'-u' | '--user')
			i=$((i + 1))
			if [ "$i" -ge "${#ARGS_LEFT[@]}" ]; then
				printf "Option -u needs a user name.\n" >&2
				exit 2
			fi
			TESTER=${ARGS_LEFT[$i]}
			;;
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

if [ "$(id -u)" -ne 0 ]; then
	printf '%s must run as root - it installs the trust anchors and changes\n' "$PROGNAME" >&2
	printf 'access control lists.\n\n' >&2
	printf '    sudo %s/%s -u %s\n' "$CANLTESTS" "$PROGNAME" "${TESTER:-$(id -un)}" >&2
	exit 1
fi

if [ -z "$TESTER" ]; then
	abort "Say who will run the tests:  sudo $PROGNAME -u <name>.  Their name goes into the ACLs."
fi
if ! getent passwd "$TESTER" > /dev/null; then
	abort "No such user: $TESTER"
fi
TESTER_GROUP=$(id -gn "$TESTER")

require_binaries make grep sed install chmod chown hostname stat

HNAME=$(hostname -f)
tmpout=/tmp/glite-canl-setup.$$.out
: > "$tmpout"
# The library's scratch file for collected error detail is named after the
# process in the current directory; as root it would leave a file the tester
# cannot remove, so it lives next to the other scratch of this script.
testerrfile=/tmp/glite-canl-setup.$$.err
trap '$SYS_RM $tmpout $testerrfile' EXIT

if [ -n "${is_html:-}" ]; then
	EXT=html
else
	EXT=txt
fi

# Where 'make -C tools install' puts the anchors, and therefore what the checks
# below look at: the installed copies, not the tester's tree that canl-common.sh
# points the tests at.
GS_DIR=/etc/grid-security

# The log has to exist before anything can be reported into it.
if [ ! -d "$STATE_DIR" ]; then
	install -d -m 0755 "$STATE_DIR" || abort "Cannot create $STATE_DIR (STATE_DIR overrides the location)."
fi
setuplog=$(state_file "canl.setup.$EXT")
envfile=$(state_file canl.env)

{
	report_header "CANL-C testbed setup on $HNAME"
	report_facts
	report_paragraph "Configured for $TESTER. Run the tests as that user: $CANLTESTS/run.sh"
	report_script "$CANLTESTS/$PROGNAME"
	report_section 'Steps'

	# --- trust anchors -------------------------------------------------------
	# The tree 'make -C tools install' copies out of is the one this script can
	# see, so it is also the one the tests will be pointed at below.
	GEN_DIR=$TEST_CERTS/grid-security
	report_step "Test CA into $GS_DIR"
	if [ ! -d "$GEN_DIR/certificates" ]; then
		report_fail_step
		report_note "nothing generated in $TEST_CERTS - as $TESTER: make -C $TESTSUITE_HOME/tools CERTS=$TEST_CERTS"
	elif make -C "$TESTSUITE_HOME/tools" install > "$tmpout" 2>&1; then
		test_done
	else
		report_fail_step
		report_note "make -C tools install failed:"
		report_dump "$tmpout"
	fi

	# --- do the anchors actually work? ---------------------------------------
	# The one thing everything else here depends on. If the installed CA cannot
	# verify the certificate that was generated with it, every test in the suite
	# will report a handshake failure and say nothing about why.
	report_step "Installed CA verifies the host certificate"
	if ! check_exec openssl; then
		test_skipped
		report_note "openssl is not installed to check with (docs/requirements.md)"
	elif openssl verify -CApath "$GS_DIR/certificates" "$GEN_DIR/hostcert.pem" > "$tmpout" 2>&1; then
		test_done
	else
		report_fail_step
		report_note "$GEN_DIR/hostcert.pem is not trusted by $GS_DIR/certificates:"
		report_dump "$tmpout"
	fi

	# --- what the tests will run ---------------------------------------------
	# The two halves come from different places, so they are reported separately:
	# emi-canl-proxy-init and emi-canl-delegation are part of the package under
	# test, and their absence says the package is not installed. The two samples
	# are built from a source tree the tester may not have fetched yet, so their
	# absence is a warning and run.sh is what refuses to start on it.
	for group in 'package:emi-canl-proxy-init emi-canl-delegation' "samples:emi-canl-client emi-canl-server"; do
		kind=${group%%:*}
		bins=${group#*:}
		missing=''
		for bin in $bins; do
			check_exec "$bin" || [ -x "$CANLTESTS/$bin" ] || missing="${missing} $bin"
		done
		report_step "CANL $kind:$bins"
		if [ -z "$missing" ]; then
			test_done
		elif [ "$kind" = package ]; then
			report_fail_step
			report_note "not installed:$missing - they come with the CANL-C package under test"
		else
			test_warning
			report_note "not built:$missing - run.sh will not start until they exist. Build them as $TESTER with"
			report_note "    make -C $CANLTESTS top_srcdir=<CANL-C source tree>"
			report_note "or point EMI_CANL_SERVER and EMI_CANL_CLIENT at already built copies."
		fi
	done

	# --- writable checkout ---------------------------------------------------
	# The tests write their $$.err scratch next to themselves. ACLs rather than
	# chown: the clone usually belongs to whoever git-cloned it.
	report_step "Checkout $TESTSUITE_HOME writable by $TESTER"
	if [ "$(stat -c %U "$TESTSUITE_HOME")" = "$TESTER" ]; then
		test_done
		report_note "owned by $TESTER already"
	elif check_exec setfacl; then
		if setfacl -R -m "u:$TESTER:rwX" "$TESTSUITE_HOME" > "$tmpout" 2>&1 \
			&& setfacl -d -m "u:$TESTER:rwX" "$TESTSUITE_HOME" "$CANLTESTS" >> "$tmpout" 2>&1; then
			test_done
		else
			report_fail_step
			report_note "setfacl failed:"
			report_dump "$tmpout"
		fi
	else
		test_warning
		report_note "setfacl is missing and the checkout belongs to $(stat -c %U "$TESTSUITE_HOME") - run.sh will refuse to start if $TESTER cannot write there"
	fi

	# --- state directory -----------------------------------------------------
	report_step "State directory $STATE_DIR owned by $TESTER"
	if chown "$TESTER:$TESTER_GROUP" "$STATE_DIR" && chmod 0755 "$STATE_DIR"; then
		test_done
	else
		report_fail_step
		report_note "run.sh cannot write its reports into it"
	fi

	# --- the environment run.sh sources --------------------------------------
	# Nothing secret: the tests read this unprivileged. The host pair is written as
	# the tester's own copy, which is the same key pair as the one installed under
	# $GS_DIR and, unlike it, readable without root. Quoted because a path is data,
	# and this file is sourced.
	report_step "Testbed environment $envfile"
	{
		printf '# Generated by %s on %s for %s. Sourced by %s/run.sh.\n' "$PROGNAME" "$(date -R)" "$TESTER" "$CANLTESTS"
		printf '# Nothing secret belongs in here - the tests read it unprivileged.\n'
		printf "export TEST_CERTS='%s'\n" "$TEST_CERTS"
		printf "export CANL_HOST_CERT='%s'\n" "$GEN_DIR/hostcert.pem"
		printf "export CANL_HOST_KEY='%s'\n" "$GEN_DIR/hostkey.pem"
		printf "export CANL_SHA2_CERT='%s'\n" "$CANL_SHA2_CERT"
		printf "export CANL_SHA2_KEY='%s'\n" "$CANL_SHA2_KEY"
	} > "$envfile"
	chmod 0644 "$envfile"
	test_done

	report_section 'Resulting testbed environment'
	report_pre "$envfile"
	report_section 'Summary'
	if [ "$REPORT_FAILURES" -eq 0 ]; then
		report_paragraph "The testbed is ready. As $TESTER: $CANLTESTS/run.sh"
	fi
	report_verdict "$REPORT_FAILURES"
	report_tail
} > "$setuplog" 2>&1

if [ "$OUTPUT_TO_FILE" -eq 1 ]; then
	cat "$setuplog" > "$OUTPUT_FILE"
else
	cat "$setuplog"
fi
printf 'Report: %s\n' "$setuplog" >&2

if [ "$REPORT_FAILURES" -gt 0 ]; then
	exit $TEST_ERROR
fi
exit $TEST_OK
