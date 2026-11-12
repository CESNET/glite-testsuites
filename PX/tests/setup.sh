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
# Prepares a machine for the PX (proxy renewal) integration tests. Run as root.
#
#   tester$  make -C tools                          # test credentials, own user
#   root#    PX/tests/setup.sh -u tester [--deploy-voms]
#   tester$  PX/tests/run.sh
#
# What it does:
#   - installs the trust anchors of the test CA into /etc/grid-security
#   - makes sure a VOMS server for the VO exists and writes the .lsc files that
#     say which server an attribute may come from (--deploy-voms deploys one, see
#     below)
#   - finds the MyProxy server the proxies are deposited at and records the DN it
#     must present
#   - checks the renewal client tools the tests drive are installed
#   - makes the checkout writable by the tester and creates $STATE_DIR
#   - writes $STATE_DIR/px.env, the environment run.sh sources
#
# It installs no packages: what has to be present is listed here, in the report and
# in docs/px.md. Deploying a VOMS server (--deploy-voms) is the one step that is
# more than a check, because a PX testbed without a VOMS server has no attributes to
# renew; it is the YAIM recipe the old px-voms-install.sh carried, kept as it was,
# minus the package installation. It asks for the database password instead of
# having one baked in, and never writes it into the report.
#
# TEST_CERTS and STATE_DIR are taken from the environment, and sudo does not pass
# yours; run 'sudo TEST_CERTS=/tmp/certs setup.sh -u tester' if the credentials were
# generated somewhere other than /tmp/certs.
#
# Everything is written to $STATE_DIR/px.setup.txt (or .html with -x), including the
# text of this script, because afterwards that is the only record of what the testbed
# was told.
# ------------------------------------------------------------------------------

PXTESTS=$(cd -- "$(dirname -- "$0")" && pwd)
source "$PXTESTS/px-common.sh"

PROGNAME=$(basename "$0")
TESTER=${SUDO_USER:-}
DEPLOY_VOMS=0
# The count of failed steps is REPORT_FAILURES, kept by report_fail_step().

showHelp()
{
	cat << EndHelpHeader
Script for preparing a testbed for the PX proxy-renewal integration tests. Run it as
root once per testbed; the tests themselves run unprivileged via run.sh.

Prerequisites:
   - the tester has generated their test credentials:  make -C tools
   - a MyProxy server on this machine, running and accepting deposits on port 7512
     (myproxy-server), configured to allow the test certificate authority
   - glite-proxy-renew, myproxy-init and myproxy-store installed (docs/px.md says
     which packages provide them)
   - a VOMS server for $PX_VO, described by a file in /etc/vomses - or the
     --deploy-voms option below

What it changes:
   - /etc/grid-security/{certificates,vomsdir,hostcert.pem,hostkey.pem}
   - /etc/vomses and /etc/grid-security/vomsdir/$PX_VO (with --deploy-voms: a
     VOMS server, its database users and its VO contents)
   - access control lists on this checkout
   - $STATE_DIR/px.env and the setup report

Returned values:
    Exit TEST_OK: The testbed is ready
    Exit TEST_ERROR: Something could not be configured, the report says what
    Exit 2: Wrong input

EndHelpHeader

	echo "Usage: sudo $PROGNAME -u TESTER [OPTIONS]"
	output_usage
	echo " -u | --user 'name'     Who will run the tests (default: \$SUDO_USER)."
	echo "     --deploy-voms      Deploy a VOMS server for $PX_VO with YAIM when"
	echo "                        /etc/vomses has none. Needs emi-voms-mysql, the"
	echo "                        glite-yaim-core package and a MySQL server; it asks"
	echo "                        for the database password."
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
		'--deploy-voms') DEPLOY_VOMS=1 ;;
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
	printf '%s must run as root - it installs the trust anchors, writes the VOMS\n' "$PROGNAME" >&2
	printf 'trust files and changes access control lists.\n\n' >&2
	printf '    sudo %s/%s -u %s\n' "$PXTESTS" "$PROGNAME" "${TESTER:-$(id -un)}" >&2
	exit 1
fi

if [ -z "$TESTER" ]; then
	abort "Say who will run the tests:  sudo $PROGNAME -u <name>.  Their name goes into the VO and the ACLs."
fi
if ! getent passwd "$TESTER" > /dev/null; then
	abort "No such user: $TESTER"
fi
TESTER_GROUP=$(id -gn "$TESTER")

require_binaries make grep sed sort tail install chmod chown cp hostname stat openssl

HNAME=$(hostname -f 2> /dev/null || hostname)
tmpout=/tmp/glite-px-setup.$$.out
: > "$tmpout"
# The library's scratch file for collected error detail is named after the process
# in the current directory; as root it would leave a file the tester cannot remove,
# so it lives next to the other scratch of this script.
testerrfile=/tmp/glite-px-setup.$$.err
# The only place a password is ever written by this script, mode 0700, and only when
# --deploy-voms runs: YAIM takes nothing else as input. Taken away again on the way
# out, whatever happened in between.
YAIMDIR=$STATE_DIR/voms-yaim
trap '$SYS_RM $tmpout $testerrfile; [ -n "${YAIMDIR:-}" ] && rm -rf -- "$YAIMDIR"' EXIT

if [ -n "${is_html:-}" ]; then
	EXT=html
else
	EXT=txt
fi

# The MyProxy port. 7512 is what myproxy-server listens on unless configured
# otherwise; the tests only ever say '-s <host>', so this is here to be able to say
# what nothing answered.
PX_PORT=${PX_PORT:-7512}

# --- deploying a VOMS server -------------------------------------------------
# The recipe of the deleted px-voms-install.sh, with the package installation taken
# out of it and the passwords asked for instead of written into the script. YAIM
# insists the passwords be in its definition files, so they are written into a
# directory only root can read, under $STATE_DIR, and removed again on the way out;
# nothing that is reported quotes them back.
#
# Whether this still works depends on there being packages for emi-voms-mysql and
# glite-yaim-core on the machine - the EMI repositories they came from are gone. It
# is here because without a VOMS server there are no attributes for the renewal to
# carry, which is most of what PX tests.
add_voms_user_w_attrs()
{
	local dn=$1 ca=$2 id=$3 mail=$4
	local longrand='' it attr

	for it in {0..40}; do longrand="${longrand}$RANDOM"; done
	voms-admin --nousercert --vo "$PX_VO" create-user "$dn" "$ca" "$id" "$mail" || return 1
	for attr in 1 2 3 4 5 6 7 8 9; do
		if [ "$attr" -eq 1 ] || [ "$attr" -eq 2 ]; then
			voms-admin --nousercert --vo "$PX_VO" set-user-attribute "$dn" "$ca" "attribute$attr" "$RANDOM"
		else
			voms-admin --nousercert --vo "$PX_VO" set-user-attribute "$dn" "$ca" "attribute$attr" "$longrand"
		fi
	done
	voms-admin --nousercert --vo "$PX_VO" add-member "/$PX_VO/Testers" "$dn" "$ca" || return 1
	voms-admin --nousercert --vo "$PX_VO" assign-role "/$PX_VO/Testers" Tester "$dn" "$ca" || return 1
	return 0
}

# A dump of output produced by a command that was given the database password. What
# the database prints back is its own error text, but nothing guarantees the word it
# complains about is not the password, so it is not pasted into a report the tester
# will keep.
dump_without_password()
{
	local scrubbed=$1.scrubbed

	awk -v p="${MYSQL_ROOT_PASSWORD:-}" -v mask='********' '
		p != "" { while ((i = index($0, p)) > 0) $0 = substr($0, 1, i - 1) mask substr($0, i + length(p)) }
		{ print }' "$1" > "$scrubbed" 2> /dev/null || cp "$1" "$scrubbed"
	report_dump "$scrubbed"
	rm -f -- "$scrubbed"
}

deploy_voms()
{
	local def=$YAIMDIR/site-info-voms.def
	local services=$YAIMDIR/services/glite-voms
	local mycnf=$YAIMDIR/my.cnf
	local cert= ca= client= attr

	if [ ! -x /opt/glite/yaim/bin/yaim ]; then
		report_note "no /opt/glite/yaim/bin/yaim - the glite-yaim-core package is not installed; docs/px.md lists what this step needs"
		return 1
	fi
	if ! check_exec voms-admin; then
		report_note "voms-admin is missing - install the VOMS server package (emi-voms-mysql)"
		return 1
	fi
	if ! check_exec mysql || ! check_exec mysqladmin; then
		report_note "the mysql client is missing - the VOMS server keeps its VO in MySQL"
		return 1
	fi

	install -d -m 0700 "$YAIMDIR/services" || return 1

	if [ -z "${MYSQL_ROOT_PASSWORD:-}" ]; then
		if [ ! -t 0 ]; then
			report_note "no MYSQL_ROOT_PASSWORD in the environment and no terminal to ask on"
			return 1
		fi
		printf 'MySQL root password for the VOMS database: '
		read -r -s MYSQL_ROOT_PASSWORD
		printf '\n'
	fi
	if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
		report_note "no database password given"
		return 1
	fi

	check_listener mysqld 3306 || check_listener mariadbd 3306 || {
		report_note "nothing is listening on 3306 - start the database (systemctl start mysqld, or mariadb) and run this again"
		return 1
	}
	# Password through a file rather than the command line: as an argument it is
	# visible to every process on the machine for as long as the command runs.
	printf '[client]\nuser=root\npassword=%s\n' "$MYSQL_ROOT_PASSWORD" > "$mycnf" || return 1
	chmod 0600 "$mycnf"

	if ! mysqladmin --defaults-extra-file="$mycnf" ping > "$tmpout" 2>&1; then
		report_note "mysqladmin could not reach the database as root:"
		dump_without_password "$tmpout"
		return 1
	fi
	# The grant the old script made by hand, so that YAIM can connect as root over
	# the host name the site definition gives it. Through standard input rather than
	# -e: the statement carries the password, and an argument is world-readable for
	# as long as the process lives. (MySQL 8 split this statement into create user
	# plus grant; docs/px.md says the deployment this step serves is EMI-era.)
	if ! mysql --defaults-extra-file="$mycnf" > "$tmpout" 2>&1 << EOSQL
grant all on *.* to 'root'@'$HNAME' identified by '$MYSQL_ROOT_PASSWORD';
EOSQL
	then
		report_note "could not grant root access from $HNAME:"
		dump_without_password "$tmpout"
		return 1
	fi

	# YAIM's own files. Written 0600 in a 0700 directory, deleted on the way out.
	{
		printf 'MYSQL_PASSWORD="%s"\n' "$MYSQL_ROOT_PASSWORD"
		printf 'SITE_NAME="%s"\n' "$HNAME"
		printf 'VOS="%s"\n' "$PX_VO"
		printf 'BDII_DELETE_DELAY=0\n'
	} > "$def"
	{
		printf '# VOMS server hostname\n'
		printf 'VOMS_HOST=%s\n' "$HNAME"
		printf "VOMS_DB_HOST='localhost'\n"
		printf 'VO_VO_ORG_VOMS_PORT=15000\n'
		printf 'VO_VO_ORG_VOMS_DB_USER=cert_mysql_user\n'
		printf 'VO_VO_ORG_VOMS_DB_PASS="%s"\n' "$MYSQL_ROOT_PASSWORD"
		printf 'VO_VO_ORG_VOMS_DB_NAME=voms_cert_mysql_db\n'
		printf 'VOMS_ADMIN_SMTP_HOST=%s\n' "${VOMS_ADMIN_SMTP_HOST:-localhost}"
		printf 'VOMS_ADMIN_MAIL=%s\n' "${VOMS_ADMIN_MAIL:-root@$HNAME}"
	} > "$services"
	chmod 0600 "$def" "$services"

	# The packaged example limits the UIDs YAIM will accept to 155/156, which no
	# modern site has; the old installer patched the example in place. Only done
	# when the file is there, and the report says so, because it is a change to a
	# packaged file.
	if [ -r /opt/glite/yaim/examples/edgusers.conf ] && grep -q '\b155\b' /opt/glite/yaim/examples/edgusers.conf; then
		sed -i -e 's/155/255/g' -e 's/156/256/g' /opt/glite/yaim/examples/edgusers.conf
		report_note "patched /opt/glite/yaim/examples/edgusers.conf (155 -> 255, 156 -> 256), as the old installer did"
	fi

	if ! /opt/glite/yaim/bin/yaim -c -s "$def" -n VOMS > "$tmpout" 2>&1; then
		report_note "YAIM failed:"
		report_dump "$tmpout"
		return 1
	fi
	report_note "YAIM configured the VOMS server"

	if [ -r /etc/profile.d/grid-env.sh ]; then
		# shellcheck source=/dev/null
		source /etc/profile.d/grid-env.sh
	fi

	# Nine attribute classes, one group, one role: the point is an attribute set big
	# enough to matter - px-test-all.sh measures the size of the attributes it ends
	# up with and only says what bug #92806 was about when they exceed 1 kB.
	for attr in 1 2 3 4 5 6 7 8 9; do
		voms-admin --vo "$PX_VO" create-attribute-class "attribute$attr" "Test attribute $attr" 0 > "$tmpout" 2>&1 \
			|| report_note "attribute$attr: $(head -n 1 "$tmpout")"
	done
	voms-admin --vo "$PX_VO" create-group Testers > "$tmpout" 2>&1 \
		|| report_note "group: $(head -n 1 "$tmpout")"
	voms-admin --vo "$PX_VO" create-role Tester > "$tmpout" 2>&1 \
		|| report_note "role: $(head -n 1 "$tmpout")"
	voms-admin --vo "$PX_VO" set-role-attribute "/$PX_VO/Testers" Role=Tester attribute3 "TestAttr$RANDOM" > "$tmpout" 2>&1 \
		|| report_note "role attribute: $(head -n 1 "$tmpout")"

	# The identities registered in the VO: the tester's and, when the tree has one,
	# the first additional client. Their DNs are read from the certificates so that
	# what the VO says and what the tester presents are the same text.
	cert="$TEST_CERTS/home/usercert.pem"
	ca=$(credentials_dn "$TEST_CERTS/trusted-ca/trusted.cert")
	if [ -r "$cert" ]; then
		client=$(credentials_dn "$cert")
		add_voms_user_w_attrs "$client" "$ca" "$TESTER" "root@$HNAME" \
			|| report_note "could not register $client in the VO"
	fi
	if [ -r "$TEST_CERTS/trusted-certs/trusted_client01.cert" ]; then
		client=$(credentials_dn "$TEST_CERTS/trusted-certs/trusted_client01.cert")
		add_voms_user_w_attrs "$client" "$ca" "$TESTER" "root@$HNAME" \
			|| report_note "could not register $client in the VO"
	fi

	install -d -m 0755 /etc/vomses
	if [ -r "/etc/voms-admin/$PX_VO/vomses" ]; then
		cp "/etc/voms-admin/$PX_VO/vomses" "/etc/vomses/$HNAME"
	else
		report_note "/etc/voms-admin/$PX_VO/vomses was not written - the VOMS server did not configure itself"
		return 1
	fi
	return 0
}

# The log has to exist before anything can be reported into it.
if [ ! -d "$STATE_DIR" ]; then
	install -d -m 0755 "$STATE_DIR" || abort "Cannot create $STATE_DIR (STATE_DIR overrides the location)."
fi
setuplog=$(state_file "px.setup.$EXT")
envfile=$(state_file px.env)

{
	report_header "PX testbed setup on $HNAME"
	report_facts
	report_paragraph "Configured for $TESTER. Run the tests as that user: $PXTESTS/run.sh"
	report_script "$PXTESTS/$PROGNAME"
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

	# The host certificate MyProxy presents. Renewal is over TLS to this machine's
	# 7512, so its certificate has to be one the tester's tools trust; installing
	# the CA above is what makes that true, and this is the check that says so.
	report_step "Host certificate $MYPROXY_HOST_CERT verifies against the installed CAs"
	if openssl verify -CApath /etc/grid-security/certificates "$MYPROXY_HOST_CERT" > "$tmpout" 2>&1; then
		test_done
	else
		report_fail_step
		report_dump "$tmpout"
		report_note "the MyProxy server will refuse connections, or the tools will refuse it"
	fi

	# --- a VOMS server to get attributes from --------------------------------
	report_step "VOMS server for $PX_VO"
	vomses=$(ls -1 /etc/vomses/* 2> /dev/null | head -n 1)
	if [ -s "${vomses:-/nonexistent}" ]; then
		test_done
		report_note "$vomses: $(cat "$vomses")"
	elif [ "$DEPLOY_VOMS" -eq 1 ]; then
		if deploy_voms; then
			test_done
		else
			report_fail_step
		fi
	else
		report_fail_step
		report_note "no entry in /etc/vomses and --deploy-voms was not given - without a VOMS server there are no attributes to renew"
		report_note "docs/px.md lists what deploying one needs; the old recipe is --deploy-voms"
	fi

	# The .lsc file names the VOMS host and the CA that signed its certificate;
	# without it a service ignores the VOMS extensions in a proxy completely.
	report_step "VOMS .lsc files in /etc/grid-security/vomsdir"
	lsc_out=$(voms_lsc_install 2>&1)
	lsc_rc=$?
	printf '%s\n' "$lsc_out" | while read -r lsc_line; do
		[ -n "$lsc_line" ] && report_note "$lsc_line"
	done
	if [ "$lsc_rc" -eq 0 ]; then
		test_done
	else
		report_fail_step
		report_note "nothing could be generated"
	fi

	# --- the service the tests talk to ---------------------------------------
	report_step "MyProxy server listening on $HNAME:$PX_PORT"
	if check_listener myproxy-server "$PX_PORT"; then
		test_done
	else
		report_fail_step
		report_note "nothing that identifies as myproxy-server holds $PX_PORT - start it and run this again"
		report_note "px-test-all.sh deposits a proxy with it, which is the whole test"
	fi

	report_step "DN the MyProxy server presents"
	MYPROXY_SERVER_DN=$(credentials_dn "$MYPROXY_HOST_CERT")
	if [ -n "$MYPROXY_SERVER_DN" ]; then
		test_done
		report_note "$MYPROXY_SERVER_DN"
		report_note "MyProxy checks this against what the server offers; the tests export it as MYPROXY_SERVER_DN"
	else
		report_fail_step
		report_note "could not read the subject of $MYPROXY_HOST_CERT"
	fi

	report_step "Renewal client tools"
	px_missing=''
	for px_bin in glite-proxy-renew myproxy-init myproxy-store voms-proxy-init voms-proxy-info; do
		check_exec "$px_bin" || px_missing="$px_missing $px_bin"
	done
	if [ -z "$px_missing" ]; then
		test_done
	else
		report_fail_step
		report_note "not on $PATH:$px_missing"
		report_note "docs/px.md says which packages provide them"
	fi

	# --- rights --------------------------------------------------------------
	# No sudoers rule: unlike LB and GridSite these tests never touch anything that
	# belongs to root. They chmod their own credentials and deposit a proxy.
	report_step "No root rights granted to $TESTER"
	test_done
	report_note "the PX tests only write their own files; if run.sh reports a permission problem, the checkout ACL below is the thing to fix"

	report_step "Checkout $TESTSUITE_HOME writable by $TESTER"
	if [ "$(stat -c %U "$TESTSUITE_HOME")" = "$TESTER" ]; then
		test_done
		report_note "owned by $TESTER already"
	elif check_exec setfacl; then
		if setfacl -R -m "u:$TESTER:rwX" "$TESTSUITE_HOME" > "$tmpout" 2>&1 \
			&& setfacl -d -m "u:$TESTER:rwX" "$TESTSUITE_HOME" "$PXTESTS" >> "$tmpout" 2>&1; then
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

	report_step "State directory $STATE_DIR owned by $TESTER"
	if chown "$TESTER:$TESTER_GROUP" "$STATE_DIR" && chmod 0755 "$STATE_DIR"; then
		test_done
	else
		report_fail_step
		report_note "run.sh cannot write its reports into it"
	fi

	# --- the environment run.sh sources --------------------------------------
	report_step "Testbed environment $envfile"
	{
		printf '# Generated by %s on %s for %s. Sourced by %s/run.sh.\n' "$PROGNAME" "$(date -R)" "$TESTER" "$PXTESTS"
		printf '# The tests read this unprivileged, so no password belongs in here -\n'
		printf '# the VOMS database password never reaches this file or the report.\n'
		printf '# Quoted throughout: this file is sourced, and a path is data.\n'
		printf "export TEST_CERTS='%s'\n" "$TEST_CERTS"
		printf "export PX_VO='%s'\n" "$PX_VO"
		printf "export PX_SERVER='%s'\n" "$HNAME"
		printf "export PX_PORT='%s'\n" "$PX_PORT"
		printf "export MYPROXY_SERVER_DN='%s'\n" "$MYPROXY_SERVER_DN"
		printf "export PX_PROXY_HOURS='%s'\n" "$PX_PROXY_HOURS"
		printf "export PX_RENEWAL_WAIT='%s'\n" "$PX_RENEWAL_WAIT"
	} > "$envfile"
	chmod 0644 "$envfile"
	test_done

	report_section 'Resulting testbed environment'
	report_pre "$envfile"
	report_section 'Summary'
	if [ "$REPORT_FAILURES" -eq 0 ]; then
		report_paragraph "The testbed is ready. As $TESTER: $PXTESTS/run.sh"
		report_paragraph "px-test-all.sh waits ${PX_RENEWAL_WAIT}s for the renewal daemon to notice the deposit; PX_RENEWAL_WAIT overrides it, docs/px.md explains what it depends on."
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
