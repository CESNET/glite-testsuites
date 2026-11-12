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
# Prepares a testbed for the LB tests and records what it did. Run as root.
#
#   root#   make -C tools install                     # or just run this script
#   root#   LB/tests/setup.sh -u tester [-t|-c|-x] [-o file]
#   tester$ LB/tests/run.sh
#
# It installs no packages (docs/requirements.md lists them), it does not deploy
# or configure the LB service itself (docs/lb.md describes that), and it writes no
# password anywhere. What it does:
#
#   - installs the test CA, CRLs, VOMS trust files and host certificate that
#     'make -C tools' generated for the tester
#   - opens PostgreSQL to the LB test role when a PostgreSQL server is present
#   - grants the tester the two read-only sudo rights lb-test-purge.pl asks for
#   - makes the checkout writable by the tester and creates $STATE_DIR
#   - writes $STATE_DIR/lb.env, the environment run.sh sources
#
# Everything is written to $STATE_DIR/lb.setup.txt (or .html with -x), including
# the text of this script, because afterwards that is the only record of what the
# testbed was told.
# ------------------------------------------------------------------------------

LBTESTS=$(cd -- "$(dirname -- "$0")" && pwd)
source "$LBTESTS/lb-common.sh"

PROGNAME=$(basename "$0")
TESTER=${SUDO_USER:-}
# The count of failed steps is REPORT_FAILURES, kept by report_fail_step().

showHelp()
{
	cat << EndHelpHeader
Script for preparing a testbed for the LB integration tests. Run it as root once
per testbed; the tests themselves run unprivileged via run.sh.

Prerequisites:
   - the tester has generated their test credentials:  make -C tools
   - LB server, logger and interlogger deployed and running (docs/lb.md)
   - the packages the tests shell out to (docs/requirements.md)

What it changes:
   - /etc/grid-security/{certificates,vomsdir,hostcert.pem,hostkey.pem}
   - pg_hba.conf of a present PostgreSQL server (backed up to .orig)
   - /etc/sudoers.d/glite-lb-test
   - access control lists on this checkout
   - $STATE_DIR/lb.env and the setup report

Returned values:
    Exit TEST_OK: The testbed is ready
    Exit TEST_ERROR: Something could not be configured, the report says what
    Exit 2: Wrong input

EndHelpHeader

	echo "Usage: sudo $PROGNAME -u TESTER [OPTIONS]"
	output_usage
	echo " -u | --user 'name'     Who will run the tests (default: \$SUDO_USER)."
}

# The lines this script reports are opened and closed with report_step,
# report_note, report_dump and report_fail_step, which tools/lib/report.sh
# provides for every setup script.

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
	printf '%s must run as root - it installs the trust anchors, drops a sudoers\n' "$PROGNAME" >&2
	printf 'rule and changes access control lists.\n\n' >&2
	printf '    sudo %s/%s -u %s\n' "$LBTESTS" "$PROGNAME" "${TESTER:-$(id -un)}" >&2
	exit 1
fi

if [ -z "$TESTER" ]; then
	abort "Say who will run the tests:  sudo $PROGNAME -u <name>.  Their name goes into sudoers and the ACLs."
fi
if ! getent passwd "$TESTER" > /dev/null; then
	abort "No such user: $TESTER"
fi
TESTER_GROUP=$(id -gn "$TESTER")

require_binaries make grep sed install chmod chown hostname stat

HNAME=$(hostname -f)
tmpout=/tmp/glite-lb-setup.$$.out
: > "$tmpout"
# The library's scratch file for collected error detail is named after the process
# in the current directory; as root it would leave a file the tester cannot
# remove, so it lives next to the other scratch of this script.
testerrfile=/tmp/glite-lb-setup.$$.err
trap '$SYS_RM $tmpout $testerrfile' EXIT

if [ -n "${is_html:-}" ]; then
	EXT=html
else
	EXT=txt
fi

# The log has to exist before anything can be reported into it.
if [ ! -d "$STATE_DIR" ]; then
	install -d -m 0755 "$STATE_DIR" || abort "Cannot create $STATE_DIR (STATE_DIR overrides the location)."
fi
setuplog=$(state_file "lb.setup.$EXT")
envfile=$(state_file lb.env)

{
	report_header "LB testbed setup on $HNAME"
	report_facts
	report_paragraph "Configured for $TESTER. Run the tests as that user: $LBTESTS/run.sh"
	report_script "$LBTESTS/$PROGNAME"
	report_section 'Steps'

	# --- trust anchors -------------------------------------------------------
	report_step "Test CA into /etc/grid-security"
	if [ ! -d "$TEST_CERTS/grid-security/certificates" ]; then
		report_fail_step
		report_note "nothing generated in $TEST_CERTS - as $TESTER: make -C $TESTSUITE_HOME/tools CERTS=$TEST_CERTS"
	elif make -C "$TESTSUITE_HOME/tools" install > "$tmpout" 2>&1; then
		test_done
	else
		report_fail_step
		report_note "make -C tools install failed:"
		report_dump "$tmpout"
	fi

	# --- PostgreSQL ----------------------------------------------------------
	# The LB server's own configuration is the administrator's business; this is
	# only the piece the tests need and nothing else provides: the rtm role that
	# the harvester test looks at, reachable over the local socket.
	report_step "PostgreSQL reachable by the LB test role"
	pg_hba=''
	for conf in /etc/postgresql/*/main/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf; do
		if [ -f "$conf" ]; then
			pg_hba=$conf
			break
		fi
	done
	if [ -z "$pg_hba" ]; then
		test_skipped
		report_note "no pg_hba.conf found - fine unless this LB server uses PostgreSQL"
	else
		if $SYS_GREP -q '^local \+all \+all \+trust' "$pg_hba"; then
			test_done
			report_note "$pg_hba already trusts local connections"
		else
			[ -e "$pg_hba.orig" ] || cp -a "$pg_hba" "$pg_hba.orig"
			{
				printf 'local all all trust\n'
				printf 'host all all 127.0.0.1/32 ident\n'
				printf 'host all all ::1/128 ident\n'
			} > "$pg_hba"
			reloaded=''
			# The three ways of talking to the server that the distributions this
			# suite has lived on have each used; the first one that works wins.
			# shellcheck disable=SC2086  # the commands are words on purpose
			for cmd in 'systemctl reload postgresql' '/sbin/service postgresql reload' '/etc/init.d/postgresql reload'; do
				if $cmd > "$tmpout" 2>&1; then
					reloaded=yes
					break
				fi
			done
			if [ -z "$reloaded" ]; then
				report_fail_step
				report_note "wrote $pg_hba (backup in $pg_hba.orig) but could not reload the server:"
				report_dump "$tmpout"
			elif createuser -U postgres -S -R -D rtm > "$tmpout" 2>&1; then
				test_done
			else
				# The role existing already is the normal case on a re-run, so this
				# is a warning rather than a failure; lb-test-harvester.sh will say
				# plainly if the role really is missing.
				test_warning
				report_note "role rtm not created:"
				report_dump "$tmpout"
			fi
		fi
	fi

	# --- sudo ----------------------------------------------------------------
	# lb-test-purge.pl runs 'sudo -n /bin/cat' on these two files and skips the
	# cron part of its check when that fails. A drop-in instead of an edit of
	# /etc/sudoers, and requiretty is turned off for the tester alone rather than
	# for everybody.
	report_step "sudo rights of $TESTER for the purge check"
	if [ ! -d /etc/sudoers.d ] || ! check_exec visudo; then
		report_fail_step
		report_note "no /etc/sudoers.d or no visudo - add by hand:"
		printf "   %s\tALL=NOPASSWD: /bin/cat /etc/cron.d/glite-lb-purge.cron, /bin/cat /var/log/messages$lf" "$TESTER"
		printf "   Defaults:%s !requiretty$lf" "$TESTER"
	else
		dropin=$(mktemp)
		{
			printf '# Installed by %s for the LB test suite.\n' "$PROGNAME"
			printf '%s\tALL=NOPASSWD: /bin/cat /etc/cron.d/glite-lb-purge.cron, /bin/cat /var/log/messages\n' "$TESTER"
			printf 'Defaults:%s !requiretty\n' "$TESTER"
		} > "$dropin"
		if visudo -cf "$dropin" > "$tmpout" 2>&1 \
			&& install -m 0440 -o root -g root "$dropin" /etc/sudoers.d/glite-lb-test; then
			test_done
		else
			report_fail_step
			report_note "the sudoers rule was not installed:"
			report_dump "$tmpout"
		fi
		rm -f "$dropin"
	fi

	# --- writable checkout ---------------------------------------------------
	# The tests write $$.err, $$_notifications.txt and cms-*.json next to
	# themselves, so the tester needs write access to the checkout. ACLs rather
	# than chown: the clone usually belongs to whoever git-cloned it.
	report_step "Checkout $TESTSUITE_HOME writable by $TESTER"
	if [ "$(stat -c %U "$TESTSUITE_HOME")" = "$TESTER" ]; then
		test_done
		report_note "owned by $TESTER already"
	elif check_exec setfacl; then
		if setfacl -R -m "u:$TESTER:rwX" "$TESTSUITE_HOME" > "$tmpout" 2>&1 \
			&& setfacl -d -m "u:$TESTER:rwX" "$TESTSUITE_HOME" "$LBTESTS" >> "$tmpout" 2>&1; then
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
	# These are the variables the generated arrange_lb_test_user.sh used to export
	# before invoking the tests. Notably absent: GLITE_MYSQL_ROOT_PASSWORD, which
	# used to be written here with a placeholder value.
	report_step "Testbed environment $envfile"
	log_fprefix=/var/spool/glite/lb-locallogger
	if [ ! -d "$log_fprefix" ]; then
		log_fprefix=/var/glite/log
	fi
	{
		printf '# Generated by %s on %s for %s. Sourced by %s/run.sh.\n' "$PROGNAME" "$(date -R)" "$TESTER" "$LBTESTS"
		printf '# The tests read this unprivileged, so nothing secret belongs in here.\n'
		printf '# GLITE_MYSQL_ROOT_PASSWORD is deliberately absent: lb-test-harvester.sh\n'
		printf '# warns when it is unset. Export it in your own shell if the MySQL root\n'
		printf '# account has a password.\n'
		# Quoted throughout: this file is sourced, and a path is data - a socket
		# or certificate directory with a space in it must not split into words.
		printf "export HNAME='%s'\n" "$HNAME"
		printf "export GLITE_WMS_QUERY_SERVER='%s:%s'\n" "$HNAME" "$GLITE_LB_SERVER_PORT"
		printf "export GLITE_WMS_NOTIF_SERVER='%s:%s'\n" "$HNAME" "$GLITE_LB_SERVER_PORT"
		printf "export GLITE_WMS_LOG_DESTINATION='%s:%s'\n" "$HNAME" "$GLITE_LB_LOGGER_PORT"
		printf "export GLITE_LB_SERVER_PORT='%s'\n" "$GLITE_LB_SERVER_PORT"
		printf "export GLITE_LB_SERVER_QPORT='%s'\n" "$GLITE_LB_SERVER_QPORT"
		printf "export GLITE_LB_SERVER_WPORT='%s'\n" "$GLITE_LB_SERVER_WPORT"
		printf "export GLITE_LB_LOGGER_PORT='%s'\n" "$GLITE_LB_LOGGER_PORT"
		printf "export GLITE_LB_IL_SOCK='%s'\n" "$GLITE_LB_IL_SOCK"
		printf "export GLITE_WMS_LBPROXY_STORE_SOCK='%s'\n" "$GLITE_WMS_LBPROXY_STORE_SOCK"
		printf "export log_fprefix='%s/dglogd.log'\n" "$log_fprefix"
		printf "export TEST_CERTS='%s'\n" "$TEST_CERTS"
	} > "$envfile"
	chmod 0644 "$envfile"
	test_done

	# --- is the service actually there? --------------------------------------
	report_step "LB server accepting connections on $HNAME:$GLITE_LB_SERVER_PORT"
	if check_socket "$HNAME" "$GLITE_LB_SERVER_PORT"; then
		test_done
	else
		report_fail_step
		report_note "nothing answered there - the LB service has to be deployed and started first (docs/lb.md), and the probe needs ./testSocket built or an nc that speaks -z"
	fi

	report_step "LB logger accepting connections on $HNAME:$GLITE_LB_LOGGER_PORT"
	if check_socket "$HNAME" "$GLITE_LB_LOGGER_PORT"; then
		test_done
	else
		report_fail_step
		report_note "nothing answered there - see docs/lb.md"
	fi

	report_section 'Resulting testbed environment'
	report_pre "$envfile"
	report_section 'Summary'
	if [ "$REPORT_FAILURES" -eq 0 ]; then
		report_paragraph "The testbed is ready. As $TESTER: $LBTESTS/run.sh"
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
