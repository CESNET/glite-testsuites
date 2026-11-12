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
# Prepares a testbed for the rOCCI tests and records what it did. Run as root.
#
#   root#    rOCCI/tests/setup.sh -u tester [-t|-c|-x] [-o file]
#   tester$  rOCCI/tests/run.sh
#
# The rOCCI server itself is not deployed here - docs/rocci.md says what has to be
# installed and serving before this is run. What this does is the three things the
# tests cannot do for themselves: install the trust anchors the server's https
# certificate is checked against, find the Apache configuration the server is
# served from so that the backend switch knows what to rewrite, and give the tester
# the one root right the suite needs - switching the backend - through a program
# installed outside the checkout and named in sudoers.
#
# TEST_CERTS and STATE_DIR are taken from the environment; export them before sudo
# when they should be somewhere else than /tmp/certs and
# /var/lib/glite-testsuites.
#
# Everything is written to $STATE_DIR/rocci.setup.txt (or .html with -x), including
# the text of this script, because afterwards that is the only record of what the
# testbed was told.
# ------------------------------------------------------------------------------

ROCITESTS=$(cd -- "$(dirname -- "$0")" && pwd)
source "$ROCITESTS/rOCCI-common.sh"

PROGNAME=$(basename "$0")
TESTER=${SUDO_USER:-}

showHelp()
{
	cat << EndHelpHeader
Script for preparing a testbed for the rOCCI integration tests. Run it as root once
per testbed; the tests themselves run unprivileged via run.sh.

Prerequisites:
   - the rOCCI server installed and serving https on \$ROCCI_PORT (11443), from
     /etc/httpd/conf.d/occi-ssl.conf or /etc/apache2/sites-available/occi-ssl, with
     a SetEnv ROCCI_SERVER_BACKEND line in it
   - the rOCCI command line client and curl installed (docs/requirements.md)
   - for the backends that are not 'dummy': the zoosync client, /etc/zoosyncrc and
     machines of those backends registered in the Zookeeper service discovery
   - the tester has generated their test credentials:  make -C tools

What it changes:
   - /etc/grid-security/certificates (the anchors the server certificate is checked
     against)
   - /usr/libexec/glite-testsuites/rOCCI-switch-backend and /etc/sudoers.d/rocci-test
   - /etc/glite-testsuites/rocci.conf, which tells that program who runs the tests
     and where to write the credentials it finds
   - access control lists on this checkout
   - $STATE_DIR/rocci.env and the setup report

It installs no packages and deploys no rOCCI server.

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
	printf '%s must run as root - it installs the trust anchors, the program the\n' "$PROGNAME" >&2
	printf 'tests sudo to switch backends, and the access control lists.\n\n' >&2
	printf '    sudo %s/%s -u %s\n' "$ROCITESTS" "$PROGNAME" "${TESTER:-$(id -un)}" >&2
	exit 1
fi

if [ -z "$TESTER" ]; then
	abort "Say who will run the tests:  sudo $PROGNAME -u <name>.  Their name goes into sudoers and the ACLs."
fi
if ! getent passwd "$TESTER" > /dev/null; then
	abort "No such user: $TESTER"
fi
TESTER_GROUP=$(id -gn "$TESTER")

require_binaries make grep sed install chmod chown hostname stat mktemp

HNAME=$(hostname -f)
tmpout=/tmp/glite-rocci-setup.$$.out
: > "$tmpout"
# The library's scratch file for collected error detail is named after the process in
# the current directory; as root it would leave a file the tester cannot remove.
testerrfile=/tmp/glite-rocci-setup.$$.err
ROCCI_CONF_DIR=/etc/glite-testsuites
ROCCI_SETUP_CONF=$ROCCI_CONF_DIR/rocci.conf
trap '$SYS_RM $tmpout $testerrfile' EXIT

if [ -n "${is_html:-}" ]; then
	EXT=html
else
	EXT=txt
fi

GS_DIR=/etc/grid-security
TOGGLE_DIR=$([ -d /usr/libexec ] && echo /usr/libexec || echo /usr/lib)/glite-testsuites
TOGGLE=$TOGGLE_DIR/rOCCI-switch-backend

# Which of the two locations the server is served from, and therefore which service
# has to be restarted when the backend changes. The helper works the same way out;
# knowing it here is what lets the report say what the testbed is.
ROCCI_CONFIG=''
ROCCI_SERVICE=''
for candidate in /etc/httpd/conf.d/occi-ssl.conf /etc/apache2/sites-available/occi-ssl; do
	[ -f "$candidate" ] || continue
	ROCCI_CONFIG=$candidate
	case "$candidate" in
		*/apache2/*) ROCCI_SERVICE=apache2 ;;
		*) ROCCI_SERVICE=httpd ;;
	esac
	break
done

# The log has to exist before anything can be reported into it.
if [ ! -d "$STATE_DIR" ]; then
	install -d -m 0755 "$STATE_DIR" || abort "Cannot create $STATE_DIR (STATE_DIR overrides the location)."
fi
setuplog=$(state_file "rocci.setup.$EXT")
envfile=$(state_file rocci.env)

{
	report_header "rOCCI testbed setup on $HNAME"
	report_facts
	report_paragraph "Configured for $TESTER. Run the tests as that user: $ROCITESTS/run.sh"
	report_script "$ROCITESTS/$PROGNAME"
	report_section 'Steps'

	# --- trust anchors ---------------------------------------------------------
	# The deployment test verifies the server's certificate with --capath, and on a
	# testbed the server holds the host certificate 'make -C tools' issued.
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

	# --- the server the tests will find ----------------------------------------
	report_step "rOCCI Apache configuration"
	if [ -z "$ROCCI_CONFIG" ]; then
		report_fail_step
		report_note "neither /etc/httpd/conf.d/occi-ssl.conf nor /etc/apache2/sites-available/occi-ssl exists"
		report_note "install the rOCCI server (docs/rocci.md) and run this again - switching backends has nothing to rewrite without it"
	elif ! grep -q '^[[:space:]]*SetEnv[[:space:]]\+ROCCI_SERVER_BACKEND' "$ROCCI_CONFIG"; then
		report_fail_step
		report_note "$ROCCI_CONFIG has no SetEnv ROCCI_SERVER_BACKEND line"
		report_note "the rOCCI server is not served from it, or it is not the packaged configuration; switching backends edits those lines"
	else
		test_done
		report_note "$ROCCI_CONFIG, restarted as $ROCCI_SERVICE"
	fi

	report_step "rOCCI server listening on $HNAME:$ROCCI_PORT"
	if check_socket 127.0.0.1 "$ROCCI_PORT"; then
		test_done
	else
		report_fail_step
		report_note "nothing answers on $ROCCI_PORT - start the server ($ROCCI_SERVICE) and run this again"
	fi

	report_step "rOCCI client and curl"
	missing=''
	for bin in "$OCCI_CLIENT" $SYS_CURL; do
		check_exec "$bin" || missing="${missing} $bin"
	done
	if [ -z "$missing" ]; then
		test_done
	else
		report_fail_step
		report_note "not installed:$missing (docs/requirements.md) - rOCCI-test-deployment.sh cannot start without them"
	fi

	# --- service discovery -----------------------------------------------------
	# Only the backends that are not 'dummy' are looked up there, so a testbed with
	# no Zookeeper is not broken; it just has one backend.
	report_step "Zoosync service discovery"
	if ! check_exec zoosync; then
		test_warning
		report_note "no zoosync client - only the 'dummy' backend can be selected (docs/requirements.md)"
	elif [ ! -f /etc/zoosyncrc ]; then
		test_warning
		report_note "/etc/zoosyncrc is missing - only the 'dummy' backend can be selected"
	else
		test_done
		report_note "backends a run selects: $ROCCI_BACKENDS"
	fi

	# --- what the tester may do as root ----------------------------------------
	# One program, installed outside the checkout so that the tester cannot edit it
	# between the sudoers check and the run, and given by exact name. Everything the
	# helper writes comes from the root-owned configuration written next to it, never
	# from the caller's arguments.
	report_step "sudo rights of $TESTER"
	if [ ! -d /etc/sudoers.d ] || ! check_exec visudo; then
		report_fail_step
		report_note "no /etc/sudoers.d or no visudo - add by hand:"
		printf '   %s\tALL=NOPASSWD: %s$lf' "$TESTER" "$TOGGLE"
	elif ! install -d -m 0755 "$TOGGLE_DIR" \
		|| ! install -m 0755 -o root -g root "$ROCITESTS/rOCCI-switch-backend.sh" "$TOGGLE"; then
		report_fail_step
		report_note "$TOGGLE could not be installed"
	else
		dropin=$(mktemp)
		{
			printf '# Installed by %s for the rOCCI test suite.\n' "$PROGNAME"
			printf '%s\tALL=NOPASSWD: %s\n' "$TESTER" "$TOGGLE"
		} > "$dropin"
		if visudo -cf "$dropin" > "$tmpout" 2>&1 \
			&& install -m 0440 -o root -g root "$dropin" /etc/sudoers.d/rocci-test; then
			test_done
			report_note "the tester switches backends with: sudo -n $TOGGLE dummy"
			report_note "this is a copy made now - changing rOCCI-switch-backend.sh means running setup.sh again"
		else
			report_fail_step
			report_note "the sudoers rule was not installed:"
			report_dump "$tmpout"
		fi
		rm -f "$dropin"
	fi

	# What the helper is allowed to know: who the tests belong to, which service to
	# restart, and where the credentials file may be written. Root-owned and mode 0644
	# - the user who runs the helper through sudo cannot change this file, which is why
	# the helper takes none of those answers from its command line.
	report_step "Switch configuration $ROCCI_SETUP_CONF"
	if install -d -m 0755 "$ROCCI_CONF_DIR" \
		&& {
			printf '# Written by %s on %s. Read by %s, which the tests run as root.\n' \
				"$PROGNAME" "$(date -R)" "$TOGGLE"
			printf '# Nothing secret belongs in here.\n'
			printf 'ROCCI_TESTER=%s\n' "$TESTER"
			printf 'ROCCI_SERVICE=%s\n' "${ROCCI_SERVICE:-httpd}"
			printf 'STATE_DIR=%s\n' "$STATE_DIR"
		} > "$ROCCI_SETUP_CONF" \
		&& chmod 0644 "$ROCCI_SETUP_CONF" && chown root:root "$ROCCI_SETUP_CONF"; then
		test_done
	else
		report_fail_step
		report_note "the switch helper will not know who to write the backend credentials for"
	fi

	# --- writable checkout -----------------------------------------------------
	# The tests write $$.tmp scratch next to themselves. ACLs rather than chown: the
	# clone usually belongs to whoever git-cloned it.
	report_step "Checkout $TESTSUITE_HOME writable by $TESTER"
	if [ "$(stat -c %U "$TESTSUITE_HOME")" = "$TESTER" ]; then
		test_done
		report_note "owned by $TESTER already"
	elif check_exec setfacl; then
		if setfacl -R -m "u:$TESTER:rwX" "$TESTSUITE_HOME" > "$tmpout" 2>&1 \
			&& setfacl -d -m "u:$TESTER:rwX" "$TESTSUITE_HOME" "$ROCITESTS" >> "$tmpout" 2>&1; then
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

	# --- state directory -------------------------------------------------------
	# Also where the credentials of the current backend land, so it belongs to the
	# tester; the credential file itself is written 0600 by the switch helper.
	report_step "State directory $STATE_DIR owned by $TESTER"
	if chown "$TESTER:$TESTER_GROUP" "$STATE_DIR" && chmod 0755 "$STATE_DIR"; then
		test_done
	else
		report_fail_step
		report_note "run.sh cannot write its reports into it"
	fi

	# --- the environment run.sh sources ----------------------------------------
	# Nothing secret: the tests read this unprivileged, and the report prints it. The
	# backend credentials are in $STATE_DIR/rocci-info.sh, which is not this file and
	# is never put into a report.
	report_step "Testbed environment $envfile"
	{
		printf '# Generated by %s on %s for %s. Sourced by %s/run.sh.\n' "$PROGNAME" "$(date -R)" "$TESTER" "$ROCITESTS"
		printf '# Nothing secret belongs in here - the tests read it unprivileged.\n'
		printf "export TEST_CERTS='%s'\n" "$TEST_CERTS"
		printf "export ROCCI_SERVER='%s'\n" "$HNAME"
		printf "export ROCCI_PORT='%s'\n" "$ROCCI_PORT"
		printf "export ROCCI_URL='%s'\n" "$ROCCI_URL"
		printf "export ROCCI_CONFIG='%s'\n" "$ROCCI_CONFIG"
		printf "export ROCCI_SERVICE='%s'\n" "$ROCCI_SERVICE"
		printf "export ROCCI_TOGGLE='%s'\n" "$TOGGLE"
		printf "export ROCCI_INFO='%s'\n" "$(state_file rocci-info.sh)"
		printf "export ROCCI_BACKENDS='%s'\n" "$ROCCI_BACKENDS"
	} > "$envfile"
	chmod 0644 "$envfile"
	test_done

	report_section 'Resulting testbed environment'
	report_pre "$envfile"
	report_section 'Summary'
	if [ "$REPORT_FAILURES" -eq 0 ]; then
		report_paragraph "The testbed is ready. As $TESTER: $ROCITESTS/run.sh"
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
