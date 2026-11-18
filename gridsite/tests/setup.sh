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
# Prepares a testbed for the GridSite tests and records what it did. Run as root.
#
#   root#   gridsite/tests/setup.sh -u tester [-t|-c|-x] [-o file]
#   tester$ gridsite/tests/run.sh
#
# It installs no packages (docs/requirements.md lists them) and it does not build
# or install GridSite itself - the package under test has to be there already,
# including its Apache config example and gridsite-delegation.cgi. What it does:
#
#   - installs the test CA, CRLs, VOMS trust files and host certificate that
#     'make -C tools' generated for the tester
#   - writes the Apache configuration for these tests out of the packaged example
#     and restarts Apache with it, on port 443
#   - makes the document root and the proxy cache writable by both the tester (who
#     drops .gacl files into them) and the server (which is asked to create files
#     in them)
#   - generates the VOMS .lsc files from /etc/vomses, which the tests read
#   - grants the tester the few exact root commands the tests still need
#   - makes the checkout writable by the tester and creates $STATE_DIR
#   - writes $STATE_DIR/gridsite.env, the environment run.sh sources
#
# TEST_CERTS and STATE_DIR are taken from the environment, and sudo does not pass
# yours; run 'sudo TEST_CERTS=/tmp/certs setup.sh -u tester' if the credentials
# were generated somewhere other than /tmp/certs.
#
# Everything is written to $STATE_DIR/gridsite.setup.txt (or .html with -x),
# including the text of this script, because afterwards that is the only record of
# what the testbed was told.
# ------------------------------------------------------------------------------

GSTESTS=$(cd -- "$(dirname -- "$0")" && pwd)
source "$GSTESTS/gridsite-common.sh"

PROGNAME=$(basename "$0")
TESTER=${SUDO_USER:-}
# The count of failed steps is REPORT_FAILURES, kept by report_fail_step().

showHelp()
{
	cat << EndHelpHeader
Script for preparing a testbed for the GridSite integration tests. Run it as root
once per testbed; the tests themselves run unprivileged via run.sh.

Prerequisites:
   - the tester has generated their test credentials:  make -C tools
   - gridsite, gridsite-commands and gridsite-service-clients installed, plus
     Apache with mod_ssl and the GridSite module (docs/gridsite.md)
   - a running Apache, listening on 443, with the GridSite module loaded
   - a VOMS server the testbed trusts, described by a file in /etc/vomses
     (the PX suite deploys one: PX/tests/setup.sh)

What it changes:
   - /etc/grid-security/{certificates,vomsdir,hostcert.pem,hostkey.pem}
   - \$HTTPD_CONFDIR/gridsite-webserver.conf (a previous one is kept as .orig)
   - ownership and access control lists on $GS_HTDOCS and $GS_PROXYCACHE
   - /etc/sudoers.d/gridsite-test and the helper it names
   - access control lists on this checkout
   - $STATE_DIR/gridsite.env and the setup report

It stops any Apache running on this machine and starts one with the configuration
it wrote. On a machine whose Apache serves anything else, do not run it.

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
	printf '%s must run as root - it installs the trust anchors, writes the Apache\n' "$PROGNAME" >&2
	printf 'configuration, restarts the server and changes access control lists.\n\n' >&2
	printf '    sudo %s/%s -u %s\n' "$GSTESTS" "$PROGNAME" "${TESTER:-$(id -un)}" >&2
	exit 1
fi

if [ -z "$TESTER" ]; then
	abort "Say who will run the tests:  sudo $PROGNAME -u <name>.  Their name goes into sudoers and the ACLs."
fi
if ! getent passwd "$TESTER" > /dev/null; then
	abort "No such user: $TESTER"
fi
TESTER_GROUP=$(id -gn "$TESTER")

require_binaries make grep sed sort tail install chmod chown cp hostname stat openssl

HNAME=$(hostname -f 2> /dev/null || hostname)
tmpout=/tmp/glite-gridsite-setup.$$.out
: > "$tmpout"
# The library's scratch file for collected error detail is named after the process
# in the current directory; as root it would leave a file the tester cannot
# remove, so it lives next to the other scratch of this script.
testerrfile=/tmp/glite-gridsite-setup.$$.err
trap '$SYS_RM $tmpout $testerrfile' EXIT

if [ -n "${is_html:-}" ]; then
	EXT=html
else
	EXT=txt
fi

# Where the distribution keeps its Apache.
HTTPD_CONFDIR=''
for dir in /etc/httpd /etc/apache2 /etc/apache; do
	if [ -d "$dir" ]; then
		HTTPD_CONFDIR=$dir
		break
	fi
done
HTTPD_SERVER_ROOT=$HTTPD_CONFDIR

# The log has to exist before anything can be reported into it.
if [ ! -d "$STATE_DIR" ]; then
	install -d -m 0755 "$STATE_DIR" || abort "Cannot create $STATE_DIR (STATE_DIR overrides the location)."
fi
setuplog=$(state_file "gridsite.setup.$EXT")
envfile=$(state_file gridsite.env)

{
	report_header "GridSite testbed setup on $HNAME"
	report_facts
	report_paragraph "Configured for $TESTER. Run the tests as that user: $GSTESTS/run.sh"
	report_script "$GSTESTS/$PROGNAME"
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

	# The tests connect to https://$HNAME, so the host certificate the server was
	# just given has to be valid for that name and trusted by what the clients -
	# curl and openssl s_client -CApath /etc/grid-security/certificates - accept.
	report_step "Host certificate for $HNAME trusted by the installed anchors"
	if openssl verify -CApath /etc/grid-security/certificates /etc/grid-security/hostcert.pem > "$tmpout" 2>&1; then
		test_done
	else
		report_fail_step
		report_note "$tmpout says:"
		report_dump "$tmpout"
	fi

	# --- the Apache configuration --------------------------------------------
	# Written out of the example the GridSite package ships, the way the generated
	# arrange script used to do it. It is a generated file, but a hand-edited one
	# from an earlier run is kept as .orig the first time.
	report_step "Apache configuration for these tests"
	if [ -z "$HTTPD_CONFDIR" ]; then
		report_fail_step
		report_note "no /etc/httpd or /etc/apache2 - Apache is not installed"
	elif ! check_exec "$SYS_APACHE"; then
		report_fail_step
		report_note "neither httpd nor apache2 is on the usual path"
	else
		GS_HTTPD_CONF=$HTTPD_CONFDIR/gridsite-webserver.conf
		conf_src=$($SYS_LS -1 /usr/share/doc/gridsite*/httpd-webserver.conf* 2> /dev/null | head -n 1)
		case "$conf_src" in
			*.gz)
				# Debian compresses everything inside /usr/share/doc.
				gzip -dc < "$conf_src" > /tmp/httpd-webserver.conf
				conf_src=/tmp/httpd-webserver.conf
			;;
		esac
		if [ -z "$conf_src" ] || [ ! -r "$conf_src" ]; then
			report_fail_step
			report_note "no httpd-webserver.conf example under /usr/share/doc/gridsite* - the gridsite package has to be installed first"
		else
			if [ -f "$GS_HTTPD_CONF" ] && [ ! -e "$GS_HTTPD_CONF.orig" ]; then
				cp -a "$GS_HTTPD_CONF" "$GS_HTTPD_CONF.orig"
			fi
			# The same six rewrites the arrange script applied: the module path of
			# the distribution, the docroot the tests write into, this host's name
			# in place of the placeholder, the proxy-limit directive left out, and
			# ServerRoot/User/Group pointed at this machine.
			sed \
				-e '1,$s!/usr/lib/httpd/modules/!modules/!' \
				-e 's!/var/www/html!'"$GS_HTDOCS"'!' \
				-e "s/FULL.SERVER.NAME/$HNAME/" \
				-e 's/\(GridSiteGSIProxyLimit\)/# \1/' \
				-e "s,^\(ServerRoot\).*,\1 $HTTPD_SERVER_ROOT," \
				-e "s/^User .*/User $GS_HTTPD_USER/" \
				-e "s/^Group .*/Group $GS_HTTPD_USER/" \
				"$conf_src" > "$GS_HTTPD_CONF"
			# Session resumption needs the server-side cache. Without SSLSessionCache
			# mod_ssl runs with the cache off: it issues no session ID below TLS 1.3,
			# and it will not take back the TLS 1.3 tickets it hands out.
			#
			# The 'shm:' scheme of the packaged example is gone from Apache 2.4.31 onwards.
			#
			# The path for the cache is relative to ServerRoot: logs/
			# is where this very configuration puts its PidFile, so it exists and the
			# server can write there.
			$SYS_SED -i '/^[#]*SSLSessionCache[ \t]/d' "$GS_HTTPD_CONF"
			{
				printf 'AddHandler cgi-script .cgi\n'
				printf 'ScriptAlias /gridsite-delegation.cgi %s\n' "$GS_CGI"
				printf 'SSLCipherSuite kEECDH:HIGH:MEDIUM:!aNULL:!MD5:!RC4:!eNULL\n'
				printf 'SSLProtocol all -SSLv2 -SSLv3\n'
				printf 'SSLHonorCipherOrder On\n'
				printf 'SSLSessionCache "shmcb:logs/ssl_scache(512000)"\n'
			} >> "$GS_HTTPD_CONF"
			# The delegation CGI is in a different place on the two families.
			if [ -z "$GS_CGI" ]; then
				report_note "gridsite-delegation.cgi not found - the delegation checks will not reach a CGI"
			fi
			# log_config is compiled into the MPM on some builds, where loading the
			# .so fails outright.
			if [ ! -f "$HTTPD_SERVER_ROOT/modules/mod_log_config.so" ]; then
				$SYS_SED -i 's/^\(LoadModule[ \t]\+log_config_module.*\)/# \1/' "$GS_HTTPD_CONF"
			fi
			# Apache 2.4 split mpm, uid and authorisation out of the core, and the
			# shmcb: session cache above is a socache provider of its own.
			for mod in mpm_prefork unixd authz_core socache_shmcb; do
				if [ -f "$HTTPD_SERVER_ROOT/modules/mod_$mod.so" ]; then
					printf 'LoadModule %s_module\tmodules/mod_%s.so\n' "$mod" "$mod" >> "$GS_HTTPD_CONF"
				fi
			done
			# CGI has to be asked for per directory since Apache 2.4.
			printf 'Options ExecCGI\n' >> "$GS_HTTPD_CONF"
			test_done
			report_note "$GS_HTTPD_CONF written from $conf_src (a previous one is in $GS_HTTPD_CONF.orig)"
		fi
	fi

	# --- the directories the tests write into --------------------------------
	# Both the tester and the server need to create files in the document root:
	# the tests drop .gacl files and a test.cgi in, and the write and upload checks
	# ask the server to create the file the ACL allows. ACLs, because the directory
	# belongs to neither of them and chown would take it away from whoever owns it.
	report_step "$GS_HTDOCS writable by $TESTER and by $GS_HTTPD_USER"
	install -d -m 0755 "$GS_HTDOCS" "$GS_PROXYCACHE"
	if ! check_exec setfacl; then
		report_fail_step
		report_note "setfacl is missing (acl package); without it the tests can only run as root"
	else
		if setfacl -R -m "u:$TESTER:rwX" -m "u:$GS_HTTPD_USER:rwX" "$GS_HTDOCS" "$GS_PROXYCACHE" > "$tmpout" 2>&1 \
			&& setfacl -R -d -m "u:$TESTER:rwX" -m "u:$GS_HTTPD_USER:rwX" "$GS_HTDOCS" "$GS_PROXYCACHE" >> "$tmpout" 2>&1; then
			test_done
			report_note "the default ACLs make the files either of them creates readable by the other"
		else
			report_fail_step
			report_note "setfacl failed:"
			report_dump "$tmpout"
		fi
	fi

	# The .lsc file holds the DN of the VOMS host and of its CA; without it the
	# server ignores the VOMS extensions entirely. voms_lsc_install() (tools/lib/
	# credentials.sh) extracts them from the live servers named in /etc/vomses -
	# here, once, rather than in every test run, because it needs no decision and
	# the tests then have something correct to read. The PX suite's setup.sh calls
	# the same function.
	report_step "VOMS .lsc files in /etc/grid-security/vomsdir"
	lsc_out=$(voms_lsc_install 2>&1)
	lsc_rc=$?
	printf '%s\n' "$lsc_out" | while read -r lsc_line; do
		[ -n "$lsc_line" ] && report_note "$lsc_line"
	done
	if [ "$lsc_rc" -eq 0 ]; then
		test_done
	else
		test_warning
		report_note "No real VOMS servers in /etc/grid-security/vomsdir"
	fi

	# --- what the tester may still do as root --------------------------------
	# Three exact chown invocations and one program of its own, which is all the
	# tests need beyond their own rights. An exact command per line, with no
	# wildcards: a rule of the form '/bin/mv /etc/* ' would hand over the machine.
	report_step "sudo rights of $TESTER"
	GS_VOMS_TOGGLE_DIR=$([ -d /usr/libexec ] && echo /usr/libexec || echo /usr/lib)/glite-testsuites
	GS_VOMS_TOGGLE=$GS_VOMS_TOGGLE_DIR/gridsite-vomsdir
	chown_bin=$(command -v chown)
	cmp_bin=$(command -v cmp)
	if [ ! -d /etc/sudoers.d ] || ! check_exec visudo; then
		report_fail_step
		report_note "no /etc/sudoers.d or no visudo - add by hand:"
		printf '   %s\tALL=NOPASSWD: %s %s %s, %s root %s, %s %s %s$lf' \
			"$TESTER" "$chown_bin" "$GS_HTTPD_USER" "$GS_HTDOCS" "$chown_bin" "$GS_HTDOCS" \
			"$chown_bin" "$GS_HTTPD_USER" "$GS_PROXYCACHE"
		printf '%s\tALL=NOPASSWD: %s -s %s %s\n' \
			"$TESTER" "$cmp_bin" /tmp/test.txt "$GS_HTDOCS"/test.txt
		printf '   %s\tALL=NOPASSWD: %s$lf' "$TESTER" "$GS_VOMS_TOGGLE"
	elif install -d -m 0755 "$GS_VOMS_TOGGLE_DIR" \
		&& install -m 0755 -o root -g root "$GSTESTS/gridsite-vomsdir-toggle.sh" "$GS_VOMS_TOGGLE"; then
		dropin=$(mktemp)
		{
			printf '# Installed by %s for the GridSite test suite.\n' "$PROGNAME"
			printf '%s\tALL=NOPASSWD: %s %s %s, %s root %s, %s %s %s\n' \
				"$TESTER" "$chown_bin" "$GS_HTTPD_USER" "$GS_HTDOCS" "$chown_bin" "$GS_HTDOCS" \
				"$chown_bin" "$GS_HTTPD_USER" "$GS_PROXYCACHE"
			printf '%s\tALL=NOPASSWD: %s -s %s %s\n' \
				"$TESTER" "$cmp_bin" /tmp/test.txt "$GS_HTDOCS"/test.txt
			printf '%s\tALL=NOPASSWD: %s\n' "$TESTER" "$GS_VOMS_TOGGLE"
		} > "$dropin"
		if visudo -cf "$dropin" > "$tmpout" 2>&1 \
			&& install -m 0440 -o root -g root "$dropin" /etc/sudoers.d/gridsite-test; then
			test_done
			report_note "$GS_VOMS_TOGGLE hides and restores /etc/grid-security/vomsdir; if a run was killed with it hidden, sudo -n $GS_VOMS_TOGGLE restore"
		else
			report_fail_step
			report_note "the sudoers rule was not installed:"
			report_dump "$tmpout"
		fi
		rm -f "$dropin"
	else
		report_fail_step
		report_note "$GS_VOMS_TOGGLE could not be installed"
	fi

	# --- writable checkout ---------------------------------------------------
	# The tests write $$.tmp and the role-comparison files next to themselves, so
	# the tester needs write access to the checkout. ACLs rather than chown: the
	# clone usually belongs to whoever git-cloned it.
	report_step "Checkout $TESTSUITE_HOME writable by $TESTER"
	if [ "$(stat -c %U "$TESTSUITE_HOME")" = "$TESTER" ]; then
		test_done
		report_note "owned by $TESTER already"
	elif check_exec setfacl; then
		if setfacl -R -m "u:$TESTER:rwX" "$TESTSUITE_HOME" > "$tmpout" 2>&1 \
			&& setfacl -d -m "u:$TESTER:rwX" "$TESTSUITE_HOME" "$GSTESTS" >> "$tmpout" 2>&1; then
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

	# --- start the server ----------------------------------------------------
	# Any Apache on this machine is stopped first: the tests need the one serving
	# the configuration above on port 443, and this is a testbed. Started this way
	# it does not come back after a reboot - run this script again, or the same two
	# commands, after one.
	report_step "Apache started with $GS_HTTPD_CONF"
	if [ ! -r "${GS_HTTPD_CONF:-/nonexistent}" ]; then
		test_skipped
		report_note "no configuration was written"
	else
		killall httpd apache2 > /dev/null 2>&1
		sleep 2
		killall -9 httpd apache2 > /dev/null 2>&1
		sleep 1
		if selinuxenabled > /dev/null 2>&1; then
			# Starting Apache from a script leaves it in a domain it will not serve
			# from on enforcing systems; runcon moves the start into the right one.
			runcon -r system_r "$SYS_APACHE" -f "$GS_HTTPD_CONF" > "$tmpout" 2>&1 \
				|| "$SYS_APACHE" -f "$GS_HTTPD_CONF" >> "$tmpout" 2>&1
		else
			"$SYS_APACHE" -f "$GS_HTTPD_CONF" > "$tmpout" 2>&1
		fi
		if check_listener "$SYS_APACHE" "$GS_PORT"; then
			test_done
		else
			report_fail_step
			report_note "nothing is listening on $GS_PORT:"
			report_dump "$tmpout"
			report_dump "$GS_HTTPD_CONF"
		fi
	fi

	report_step "GridSite module loaded into it"
	if "$SYS_APACHE" -f "$GS_HTTPD_CONF" -t -D DUMP_MODULES 2>&1 | $SYS_GREP -q gridsite_module; then
		test_done
	else
		report_fail_step
		report_note "gridsite_module is not in '$SYS_APACHE -f $GS_HTTPD_CONF -t -D DUMP_MODULES' - is the GridSite package installed?"
	fi

	# --- the environment run.sh sources --------------------------------------
	report_step "Testbed environment $envfile"
	{
		printf '# Generated by %s on %s for %s. Sourced by %s/run.sh.\n' "$PROGNAME" "$(date -R)" "$TESTER" "$GSTESTS"
		printf '# The tests read this unprivileged, so nothing secret belongs in here.\n'
		printf '# Quoted throughout: this file is sourced, and a path is data.\n'
		printf "export TEST_CERTS='%s'\n" "$TEST_CERTS"
		printf "export GS_SERVER='%s'\n" "$HNAME"
		printf "export GS_PORT='%s'\n" "$GS_PORT"
		printf "export GS_HTDOCS='%s'\n" "$GS_HTDOCS"
		printf "export GS_PROXYCACHE='%s'\n" "$GS_PROXYCACHE"
		printf "export GS_HTTPD_USER='%s'\n" "$GS_HTTPD_USER"
		printf "export GS_HTTPD_CONF='%s'\n" "$GS_HTTPD_CONF"
		printf "export GS_CGI='%s'\n" "$GS_CGI"
		printf "export GS_VOMS_TOGGLE='%s'\n" "$GS_VOMS_TOGGLE"
	} > "$envfile"
	chmod 0644 "$envfile"
	test_done

	report_section 'Resulting testbed environment'
	report_pre "$envfile"
	report_section 'Summary'
	if [ "$REPORT_FAILURES" -eq 0 ]; then
		report_paragraph "The testbed is ready. As $TESTER: $GSTESTS/run.sh"
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
