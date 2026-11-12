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
# Points the rOCCI server at one of its backends and says what credentials the
# tests should then use against it. Root only - setup.sh installs this under
# /usr/libexec/glite-testsuites and names it in /etc/sudoers.d so that the tester
# can switch backends without being given a root shell:
#
#   tester$  sudo -n /usr/libexec/glite-testsuites/rOCCI-switch-backend opennebula-4.12 1200
#
# Switching has always meant the same three things: ask the Zookeeper service
# discovery for a running machine of that backend together with the credentials its
# tags carry, write them into the SetEnv lines of the Apache configuration the
# rOCCI server is served from, and restart that server. This then writes the user
# and password the deployment test authenticates with, owned by the tester.
#
# Where it writes comes from /etc/glite-testsuites/rocci.conf, which setup.sh
# writes and only root can change - never from the command line, because the
# command line belongs to the unprivileged caller. That is what makes the single
# sudo rule it needs safe to grant.
#
# Nothing from the repository is sourced: the installed copy has to keep working
# when the checkout is somewhere else, and it is the file sudoers names.
#
# Exit codes, which run.sh reports per backend:
#     0  the server runs on that backend now
#     1  broken - the rOCCI Apache configuration, or restarting the server
#     2  wrong input
#     3  that backend is not available on this testbed: no service discovery, or
#        nothing of that kind registered in it. Not a failure of the server.
# ------------------------------------------------------------------------------

PROGNAME=$(basename "$0")

STATE_DIR=${STATE_DIR:-/var/lib/glite-testsuites}
ROCCI_TESTER=${ROCCI_TESTER:-}
ROCCI_SERVICE=${ROCCI_SERVICE:-}
# Written by rOCCI/tests/setup.sh: root-owned mode 0644, plain assignments.
CONF_FILE=${ROCCI_SETUP_CONF:-/etc/glite-testsuites/rocci.conf}
# Where setup.sh installs this. The hint given to an unprivileged caller names that
# path - the sudoers rule is for the installed copy, not for the file in a checkout.
TOGGLE_PATH=${ROCCI_TOGGLE_PATH:-/usr/libexec/glite-testsuites/rOCCI-switch-backend}

showHelp()
{
	cat << EndHelpHeader
Points the rOCCI server on this machine at one of its backends.

Backends other than 'dummy' are looked up in the Zookeeper service discovery the
zoosync client is configured for (/etc/zoosyncrc): this waits up to WAIT seconds for
a machine of that backend to be running, reads the credentials its tags carry,
writes them into the SetEnv lines of the Apache configuration serving rOCCI, and
restarts that server. The user and password to authenticate against the server with
are then written to \$STATE_DIR/rocci-info.sh, owned by the tester setup.sh was told
about. The password never appears in the output.

'dummy' is the backend the server uses before any cloud is involved and needs no
service discovery at all.

Returned values:
    Exit 0: The server runs on that backend
    Exit 1: Broken - the rOCCI Apache configuration or restarting the server
    Exit 2: Wrong input
    Exit 3: That backend is not available on this testbed

EndHelpHeader

	echo "Usage: sudo $PROGNAME [OPTIONS] BACKEND [WAIT]"
	echo " BACKEND               dummy | opennebula-VERSION | amazon"
	echo " WAIT                  seconds to wait for the backend (default 1800)"
	echo "Options:"
	echo " -h | --help           Show this help message."
}

# The command line is checked before anything is touched, and before the refusal to
# run unprivileged, so that a mistyped invocation says what was mistyped.
backend=''
wait_for=''
while [ $# -gt 0 ]; do
	case "$1" in
		'-h' | '--help')
			showHelp
			exit 2
			;;
		'-*')
			printf "Unknown option '%s'.\n" "$1" >&2
			printf "Try '%s -h'.\n" "$PROGNAME" >&2
			exit 2
			;;
		*)
			if [ -z "$backend" ]; then
				backend=$1
			elif [ -z "$wait_for" ]; then
				wait_for=$1
			else
				printf "Too many arguments, '%s' is one too many.\n" "$1" >&2
				printf "Try '%s -h'.\n" "$PROGNAME" >&2
				exit 2
			fi
			;;
	esac
	shift
done

if [ -z "$backend" ]; then
	printf '%s says which backend to switch to.\n\n' "$PROGNAME" >&2
	showHelp >&2
	exit 2
fi
: "${wait_for:=1800}"
case "$wait_for" in
	'' | *[!0-9]*)
		printf "The waiting time has to be a number of seconds, not '%s'.\n" "$wait_for" >&2
		exit 2
		;;
esac

# The name is checked here rather than where it is acted on, so that a misspelled
# backend says so instead of being reported as a testbed that cannot be reached - and
# so that the answer to a typo does not depend on being root.
case "$backend" in
	dummy | 'opennebula' | 'opennebula-'* | amazon) ;;
	*)
		printf "Unknown rOCCI backend '%s' - it is dummy, opennebula-VERSION or amazon.\n" "$backend" >&2
		exit 2
		;;
esac

if [ "$(id -u)" -ne 0 ]; then
	printf '%s must run as root - it rewrites the Apache configuration of the rOCCI\n' "$PROGNAME" >&2
	printf 'server and restarts that server.\n\n' >&2
	printf 'setup.sh installs it where sudoers allows it to be run from:\n\n' >&2
	printf '    sudo -n %s %s %s\n' "$TOGGLE_PATH" "$backend" "$wait_for" >&2
	exit 1
fi

if [ -r "$CONF_FILE" ]; then
	# shellcheck source=/dev/null
	source "$CONF_FILE"
fi

if [ -z "$ROCCI_TESTER" ]; then
	printf '%s does not know who runs the tests - %s is missing or names no ROCCI_TESTER.\n' \
		"$PROGNAME" "$CONF_FILE" >&2
	printf 'Run rOCCI/tests/setup.sh as root first.\n' >&2
	exit 1
fi
if ! getent passwd "$ROCCI_TESTER" > /dev/null; then
	printf "No such user '%s' as written in %s.\n" "$ROCCI_TESTER" "$CONF_FILE" >&2
	exit 1
fi

# --- the configuration the server is served from ---------------------------------
# The two locations the packaged rOCCI uses, in the order the suite tried them
# before. Nothing else is a candidate: this file is rewritten by a program the
# tester can run as root.
rocci_conf=''
for candidate in /etc/httpd/conf.d/occi-ssl.conf /etc/apache2/sites-available/occi-ssl; do
	[ -f "$candidate" ] || continue
	rocci_conf=$candidate
	if [ -z "$ROCCI_SERVICE" ]; then
		case "$candidate" in
			*/apache2/*) ROCCI_SERVICE=apache2 ;;
			*) ROCCI_SERVICE=httpd ;;
		esac
	fi
	break
done
if [ -z "$rocci_conf" ]; then
	printf 'Nothing rOCCI is served from - neither /etc/httpd/conf.d/occi-ssl.conf nor\n' >&2
	printf '/etc/apache2/sites-available/occi-ssl exists. Install the rOCCI server.\n' >&2
	exit 1
fi
# The SetEnv lines are what carries the backend selection at all. A configuration
# without them would swallow every edit below silently and leave the server on
# whatever backend it already had.
if ! grep -q '^[[:space:]]*SetEnv[[:space:]]\+ROCCI_SERVER_BACKEND' "$rocci_conf"; then
	printf '%s has no SetEnv ROCCI_SERVER_BACKEND line, so switching it can do nothing.\n' "$rocci_conf" >&2
	exit 1
fi

# --- quoting ---------------------------------------------------------------------
# What ends up in a sed replacement here is passwords and URLs that came out of the
# service discovery, so a backslash, an '&' or the delimiter in them would otherwise
# mean something else. What ends up in the file the tests source is likewise data.
sed_value()
{
	printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

sh_quote()
{
	printf "'%s'" "$(printf '%s' "$1" | sed -e "s/'/'\\\\''/g")"
}

# What zoosync prints when it succeeds is shell assignments carrying credentials, and
# when it fails its output may contain the same lines. Nothing of that belongs in a
# report an unprivileged run writes, so anything that reads like an assignment is
# withheld and only its count is said.
print_without_secrets()
{
	printf '%s\n' "$1" | awk '
		/^[A-Za-z_][A-Za-z0-9_]*=/ { hidden++; next }
		{ print }
		END { if (hidden) printf "(%d line(s) carrying credentials withheld)\n", hidden }'
}

# The expression and the check for one SetEnv line. The value is compared literally,
# because a password is not a regular expression.
setenv_expr()
{
	printf '^\\([[:space:]]*SetEnv[[:space:]]\\+%s[[:space:]]\\+\\).*' "$1"
}

setenv_is()
{
	local name=$1 want=$2 current
	current=$(sed -n "s/^[[:space:]]*SetEnv[[:space:]]\\+$name[[:space:]]\\+\\(.*\\)$/\1/p" "$rocci_conf" | tail -n 1)
	[ "$current" = "$want" ]
}

# --- what the backend needs ------------------------------------------------------
provider_host=''
backend_kind=''
switch_user=''
switch_password=''
# The user the tests are told to authenticate as; for OpenNebula it is the admin,
# which is what the suite has always handed over.
report_user=''

# zoosync prints shell assignments, which is how the suite read the discovery before
# as well; only its own output is executed, and only after its exit status is known.
service_discovery()
{
	local backend_full=$1 waiting=$2 name='' tags='' out rc
	local rocci_pair admin_pair

	case "$backend_full" in
		'opennebula'*)
			name="SERVICE_OPENNEBULA_$(printf '%s' "${backend_full#opennebula-}" | tr '[:lower:].' '[:upper:]_')"
			tags='_rocci _oneadmin'
			;;
		amazon)
			name=SERVICE_AMAZON
			tags='_aws_id _aws_key'
			;;
	esac

	if ! command -v zoosync > /dev/null; then
		printf 'No zoosync client installed, so %s cannot be looked up (docs/requirements.md).\n' "$backend_full" >&2
		return 3
	fi
	if [ ! -f /etc/zoosyncrc ]; then
		printf 'Zoosync is not configured - /etc/zoosyncrc does not exist.\n' >&2
		return 3
	fi

	out=$(zoosync --service "$backend_full" --wait "$waiting" wait 2>&1); rc=$?
	if [ "$rc" -ne 0 ] || ! eval "$out"; then
		printf 'Waiting for a running %s failed:\n%s\n' "$backend_full" "$(print_without_secrets "$out")" >&2
		return 3
	fi
	if [ -z "${SERVICES:-}" ]; then
		printf '%s is not registered in the Zookeeper service discovery.\n' "$backend_full" >&2
		return 3
	fi
	eval "provider_host=\${${name}:-}"
	if [ -z "$provider_host" ]; then
		printf '%s is registered but %s is empty - which machine of that backend to use is unknown.\n' \
			"$backend_full" "$name" >&2
		return 3
	fi

	# $tags is two words on purpose - they are the names of the tags to read.
	# shellcheck disable=SC2086
	out=$(zoosync --service "$backend_full" --hostname "$provider_host" read-tag $tags 2>&1); rc=$?
	if [ "$rc" -ne 0 ] || ! eval "$out"; then
		printf 'Reading the tags of %s on %s failed:\n%s\n' \
			"$backend_full" "$provider_host" "$(print_without_secrets "$out")" >&2
		return 3
	fi

	# The tags are 'user:password' pairs. A password may itself contain a colon, so
	# the split is at the first one only - which is what cut -d: -f1 and -f2- did.
	case "$backend_full" in
		'opennebula'*)
			eval "rocci_pair=\${${name}_TAG__ROCCI:-}"
			eval "admin_pair=\${${name}_TAG__ONEADMIN:-}"
			if [ -z "$rocci_pair" ] || [ -z "$admin_pair" ]; then
				printf 'The tags of %s on %s carry no _rocci and _oneadmin credentials.\n' \
					"$backend_full" "$provider_host" >&2
				return 3
			fi
			switch_user=${rocci_pair%%:*}
			switch_password=${rocci_pair#*:}
			report_user=${admin_pair%%:*}
			rocci_password=${admin_pair#*:}
		;;
		amazon)
			eval "switch_user=\${${name}_TAG__AWS_ID:-}"
			eval "switch_password=\${${name}_TAG__AWS_KEY:-}"
			if [ -z "$switch_user" ] || [ -z "$switch_password" ]; then
				printf 'The tags of %s on %s carry no _aws_id and _aws_key credentials.\n' \
					"$backend_full" "$provider_host" >&2
				return 3
			fi
			report_user=$switch_user
			rocci_password=$switch_password
		;;
	esac
	return 0
}

case "$backend" in
	'dummy')
		backend_kind=dummy
		switch_user=dummyuser
		switch_password=dummypassword
		report_user=dummyuser
		rocci_password=dummypassword
	;;
	'opennebula'*)
		backend_kind=opennebula
		service_discovery "$backend" "$wait_for" || exit $?
	;;
	amazon)
		backend_kind=ec2
		service_discovery "$backend" "$wait_for" || exit $?
	;;
	*)
		printf "Unknown rOCCI backend '%s' - it is dummy, opennebula-VERSION or amazon.\n" "$backend" >&2
		exit 2
	;;
esac

# --- the edits -------------------------------------------------------------------
# The values go into a sed script file rather than onto its command line: they are
# credentials, and an argument would show them in the process list of everyone on
# the machine.
sedscript=$(mktemp) || {
	echo 'Cannot make a temporary file for the configuration edits.' >&2
	exit 1
}
chmod 600 "$sedscript"
trap 'rm -f "$sedscript"' EXIT INT TERM

edits=''
add_edit()
{
	printf 's|%s|\\1%s|\n' "$(setenv_expr "$1")" "$(sed_value "$2")" >> "$sedscript"
	edits="${edits:+$edits }$1"
}

add_edit ROCCI_SERVER_BACKEND "$backend_kind"
case "$backend_kind" in
	opennebula)
		add_edit ROCCI_SERVER_ONE_USER "$switch_user"
		add_edit ROCCI_SERVER_ONE_PASSWD "$switch_password"
		add_edit ROCCI_SERVER_ONE_XMLRPC "http://$provider_host:2633/RPC2"
	;;
	ec2)
		add_edit ROCCI_SERVER_EC2_AWS_ACCESS_KEY_ID "$switch_user"
		add_edit ROCCI_SERVER_EC2_AWS_SECRET_ACCESS_KEY "$switch_password"
	;;
esac

if ! sed -i -f "$sedscript" "$rocci_conf"; then
	printf 'Editing %s failed.\n' "$rocci_conf" >&2
	exit 1
fi
# sed's substitution only rewrites a line that is already there. Saying so now beats
# every later test failing against a server that is still on the old backend.
for name in $edits; do
	case "$name" in
		ROCCI_SERVER_BACKEND) want=$backend_kind ;;
		ROCCI_SERVER_ONE_USER) want=$switch_user ;;
		ROCCI_SERVER_ONE_PASSWD) want=$switch_password ;;
		ROCCI_SERVER_ONE_XMLRPC) want="http://$provider_host:2633/RPC2" ;;
		ROCCI_SERVER_EC2_AWS_ACCESS_KEY_ID) want=$switch_user ;;
		ROCCI_SERVER_EC2_AWS_SECRET_ACCESS_KEY) want=$switch_password ;;
	esac
	if ! setenv_is "$name" "$want"; then
		printf '%s has no SetEnv %s line, so there is nothing to write the %s into.\n' \
			"$rocci_conf" "$name" "$([ "$name" = ROCCI_SERVER_BACKEND ] && echo backend || echo credentials)" >&2
		exit 1
	fi
done

# --- restart ---------------------------------------------------------------------
# systemctl took the arguments where the older 'service' script puts the action last,
# so the two are written out rather than one command held in a variable.
if command -v systemctl > /dev/null; then
	restart_out=$(systemctl restart "$ROCCI_SERVICE" 2>&1)
	rc=$?
else
	restart_out=$(service "$ROCCI_SERVICE" restart 2>&1)
	rc=$?
fi
if [ "$rc" -ne 0 ]; then
	printf 'Restarting %s failed:\n%s\n' "$ROCCI_SERVICE" "$restart_out" >&2
	exit 1
fi

# --- what the tests authenticate with --------------------------------------------
# Owned by the tester and readable by nobody else: it holds a password. Written in
# the destination directory and moved into place, so a test never sources a half
# written file.
[ -d "$STATE_DIR" ] || install -d -m 0755 "$STATE_DIR" || {
	printf 'Cannot create %s.\n' "$STATE_DIR" >&2
	exit 1
}
infofile=$STATE_DIR/rocci-info.sh
tmpinfo=$(mktemp "$STATE_DIR/.rocci-info.XXXXXX") || {
	printf 'Cannot make a temporary file in %s.\n' "$STATE_DIR" >&2
	exit 1
}
{
	printf '# Written by %s on %s for %s. Sourced by the rOCCI tests.\n' \
		"$PROGNAME" "$(date -R)" "$ROCCI_TESTER"
	printf 'ROCCI_INFO_BACKEND=%s\n' "$(sh_quote "$backend")"
	printf 'one_host=%s\n' "$(sh_quote "$provider_host")"
	printf 'rocci_user=%s\n' "$(sh_quote "$report_user")"
	printf 'rocci_password=%s\n' "$(sh_quote "$rocci_password")"
} > "$tmpinfo"
chmod 0600 "$tmpinfo"
chown "$ROCCI_TESTER": "$tmpinfo"
mv -f "$tmpinfo" "$infofile" || {
	printf 'Could not put %s in place.\n' "$infofile" >&2
	rm -f "$tmpinfo"
	exit 1
}

# No password in any of this; the user name and the host are not secret and are what
# a report needs to say which machine was tested.
printf 'rOCCI backend: %s (%s)\n' "$backend" "$backend_kind"
[ -z "$provider_host" ] || printf 'provider: %s\n' "$provider_host"
printf 'configuration: %s\n' "$rocci_conf"
printf 'service restarted: %s\n' "$ROCCI_SERVICE"
printf 'credentials for the tests: %s as %s, in %s\n' "$report_user" "$backend" "$infofile"
exit 0
