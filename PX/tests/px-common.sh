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
# Definitions of functions and variables common to the PX test scripts
#
# What is here is only what PX needs: which MyProxy server the proxy gets deposited
# at and renewed from, how long the proxy the renewal is watched on lives, and how
# long the test waits for the renewal to happen.
#
# Everything generic - the output modes and the test_* verbs, the SYS_* binary
# names, check_binaries(), check_credentials() and the rest - lives in tools/lib/
# and arrives through testenv.sh, sourced below. It used to be duplicated in this
# file, and on top of that every PX test sourced ../../LB/tests/lb-common.sh as
# well, so LB's definitions won over these ones.
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
# sourced here as well so that a test run by hand from this directory sees the same
# server and the same DN. Everything below only fills in what is unset.
PX_ENV_FILE=${PX_ENV:-$(state_file px.env)}
if [ -r "$PX_ENV_FILE" ]; then
	# shellcheck source=/dev/null
	source "$PX_ENV_FILE"
fi
credentials_env

# The VO the attributes come from and the MyProxy server the proxy is deposited at,
# which is what 'glite-proxy-renew -s' is given. The tests used to have both spelled
# out at every call site.
PX_VO=${PX_VO:-vo.org}
PX_SERVER=${PX_SERVER:-localhost}
export PX_VO PX_SERVER

# The port that server answers on. run.sh checks it before starting anything, and
# the myproxy clients are not given a -p on the command line - they read this one
# variable, which is why it is exported under the name they look for as well as the
# name the env file carries. 7512 is the port IANA assigned to MyProxy and the one
# the server listens on unless told otherwise.
PX_PORT=${PX_PORT:-7512}
export PX_PORT MYPROXY_SERVER_PORT=$PX_PORT

# MyProxy identifies the server by certificate rather than by name, and refuses the
# connection when the DN it gets is not the one it was configured with - so the test
# has to say the DN of the certificate the server actually holds. setup.sh reads it
# off the host certificate of the machine serving and records both; what is here is
# the same answer computed on the spot, for a test run by hand. The machine's own
# certificate first, the generated one second: 'make -C tools install' installs the
# generated one into /etc/grid-security, which is what a testbed has.
if [ -z "${MYPROXY_HOST_CERT:-}" ]; then
	for px_hostcert in /etc/grid-security/hostcert.pem "$TEST_CERTS/grid-security/hostcert.pem"; do
		if [ -r "$px_hostcert" ]; then
			MYPROXY_HOST_CERT=$px_hostcert
			break
		fi
	done
fi
MYPROXY_HOST_CERT=${MYPROXY_HOST_CERT:-/etc/grid-security/hostcert.pem}
: "${MYPROXY_SERVER_DN:=$(credentials_dn "$MYPROXY_HOST_CERT" 2> /dev/null)}"
export MYPROXY_HOST_CERT MYPROXY_SERVER_DN

# px-test-all.sh deposits a proxy, waits, and then compares the lifetime of the
# renewed copy with the one it deposited. Both numbers are about a proxy that is
# going to expire soon, so the proxy it works on is deliberately short-lived, and
# the wait is what the renewal daemon needs to notice the deposit. Override either
# when the deployment polls faster or slower than the default.
PX_PROXY_HOURS=${PX_PROXY_HOURS:-1}
PX_RENEWAL_WAIT=${PX_RENEWAL_WAIT:-1800}
export PX_PROXY_HOURS PX_RENEWAL_WAIT

# px_regen_proxy [HOURS] - issue a fresh proxy and publish it where the GSI tools
# look.
#
# This is the mid-test regeneration px-test-all.sh has always needed: to show that a
# renewal replaced what was deposited, something has to replace the deposited proxy
# while the test is running. It used to run the deleted lb-generate-fake-proxy.sh
# from the test directory; the tool does the same thing and is what setup.sh and
# run.sh point at too, so there is one way credentials appear. Returns what make
# returns; prints where the proxy went.
px_regen_proxy()
{
	local hours=${1:-$PX_PROXY_HOURS}

	make -C "$TESTSUITE_HOME/tools" proxy \
		CERTS="$TEST_CERTS" PROXY="$X509_USER_PROXY" HOURS="$hours" VOS="$PX_VO"
}
