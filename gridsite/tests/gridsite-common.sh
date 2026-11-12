# $Header$
#
# Copyright (c) Members of the EGEE Collaboration. 2004-2010.
# See http://www.eu-egee.org/partners for details on the copyright holders.
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
# Definitions of functions and variables common to the GridSite test scripts
#
# What is here is only what GridSite needs: where the Apache serving these tests
# keeps its document root and its proxy cache, which identity it runs as, and the
# two helpers that let an unprivileged run do the handful of things on this
# machine that belong to root.
#
# Everything generic - the output modes and the test_* verbs, the SYS_* binary
# names, check_binaries(), check_socket(), check_listener(), ping_host(), the
# packaging and build checkers and the credential helpers - lives in tools/lib/
# and arrives through testenv.sh, sourced below. It used to be duplicated in this
# file, including a check_socket() whose fallback probed localhost:22 and never
# looked at the host it was given.
#
# ------------------------------------------------------------------------------

# read common definitions and functions - walking up from this file, so that
# neither the current directory nor the way the test was invoked matters
TEST_COMMON_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIBROOT=$TEST_COMMON_DIR
while [ ! -r "$LIBROOT/tools/lib/testenv.sh" ] && [ "$LIBROOT" != "/" ]; do
	LIBROOT=$(dirname -- "$LIBROOT")
done
if [ ! -r "$LIBROOT/tools/lib/testenv.sh" ]; then
	printf "Common definitions 'tools/lib/testenv.sh' not found above '${TEST_COMMON_DIR}'!\n"
	exit 2
fi
source "$LIBROOT/tools/lib/testenv.sh"

ulimit -c unlimited

# What setup.sh learned about this deployment. The drivers source it too; it is
# sourced here as well so that a test run by hand from this directory sees the
# same paths, which is what the old hardcoded /var/www/htdocs and
# /etc/grid-security/certificates were a stand-in for. Everything below only
# fills in what is unset.
GS_ENV_FILE=${GS_ENV:-$(state_file gridsite.env)}
if [ -r "$GS_ENV_FILE" ]; then
	# shellcheck source=/dev/null
	source "$GS_ENV_FILE"
fi
credentials_env

# The Apache these tests talk to and the machine it serves. GS_SERVER is what the
# tests put in the URL and in SNI; it has to be the name the host certificate is
# valid for, which setup.sh determined and recorded.
GS_SERVER=${GS_SERVER:-$(hostname -f 2> /dev/null || hostname)}
GS_PORT=${GS_PORT:-443}
GS_URL=${GS_URL:-https://$GS_SERVER:$GS_PORT}

# Where the server keeps what the tests write into it. The document root has to be
# writable by the tester (the tests drop .gacl files and a test.cgi into it) and by
# the server (the write and upload checks make it create files there); setup.sh
# does that with ACLs for both, because the directory belongs to neither.
GS_HTDOCS=${GS_HTDOCS:-/var/www/htdocs}
GS_PROXYCACHE=${GS_PROXYCACHE:-/var/www/proxycache}

# The identity Apache runs as, which the tests need whenever they have to make a
# path writable by it. Debian and Red Hat name the same role differently.
if [ -z "${GS_HTTPD_USER:-}" ]; then
	if getent passwd www-data > /dev/null 2>&1; then
		GS_HTTPD_USER=www-data
	else
		GS_HTTPD_USER=apache
	fi
fi

# Trust anchors for curl's --capath. The generated CA is installed into
# /etc/grid-security/certificates by 'make -C tools install', but a tester working
# against $TEST_CERTS alone should not have to have installed it system-wide.
GS_CAPATH=${GS_CAPATH:-${X509_CERT_DIR:-/etc/grid-security/certificates}}

# Apache. The two names are what the packaging calls it on the two families.
if [ -f /usr/sbin/apache2 ]; then
	SYS_APACHE=apache2
else
	SYS_APACHE=httpd
fi
GS_HTTPD_CONF=${GS_HTTPD_CONF:-}

# The delegation CGI, which the Apache configuration points ScriptAlias at. The
# two families install the same program in different places, and setup.sh records
# which one it used.
if [ -z "${GS_CGI:-}" ]; then
	for gs_cgi in /usr/sbin/gridsite-delegation.cgi \
		/usr/libexec/gridsite/cgi-bin/gridsite-delegation.cgi \
		/usr/lib/gridsite/cgi-bin/gridsite-delegation.cgi; do
		if [ -x "$gs_cgi" ]; then
			GS_CGI=$gs_cgi
			break
		fi
	done
fi
GS_CGI=${GS_CGI:-/usr/sbin/gridsite-delegation.cgi}

VOMSPROXYINFO=voms-proxy-info

# gs_chown OWNER PATH - make a path belong to the server, or say why not.
#
# As root this is chown, as it always was. Unprivileged it is 'sudo -n chown',
# which works only with the rule setup.sh installs. When neither works it is
# nothing at all, and that is not a failure of the check that called it: setup.sh
# already made the document root and the proxy cache writable by the server with
# ACLs, so ownership is not what any of these tests measures - it is only the way
# the tests used to obtain that state while they ran as root.
gs_chown()
{
	local owner=$1 path=$2

	if [ "$(id -u)" -eq 0 ]; then
		chown "$owner" "$path" 2>> "$testerrfile" && return 0
	elif check_exec sudo && sudo -n chown "$owner" "$path" 2>> "$testerrfile"; then
		return 0
	fi
	update_error "cannot chown $path to $owner"
	return $TEST_ERROR
}

# gs_vomsdir hide|restore - take the system VOMS trust directory out of the way and
# put it back, which is how gridsite-test-all.sh proves that mod_gridsite really
# reads the .lsc files.
#
# It goes through a small program setup.sh installed and named in
# /etc/sudoers.d, rather than 'sudo mv /etc/grid-security/vomsdir/* ...' from here:
# a sudoers rule for mv with a wildcard would let this run move anything on the
# machine, and a test interrupted between hiding and restoring would leave the
# testbed with no CA files at all. The installed program keeps its own copy and
# restores on exit.
gs_vomsdir()
{
	local what=$1
	local prog=${GS_VOMS_TOGGLE:-/usr/libexec/glite-testsuites/gridsite-vomsdir}

	if [ ! -x "$prog" ]; then
		update_error "$prog is not installed"
		return $TEST_ERROR
	fi
	if ! sudo -n "$prog" "$what" 2>> "$testerrfile"; then
		update_error "sudo -n $prog $what failed"
		return $TEST_ERROR
	fi
	return $TEST_OK
}
