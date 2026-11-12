#The work represented by this source file is partially or entirely funded
#by the EGI-InSPIRE project through the European Commission's 7th Framework
#Programme (contract # INFSO-RI-261323)
#
#Copyright (c) 2014 CESNET
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#http://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.
#
# ------------------------------------------------------------------------------
# Definitions of functions and variables common to the rOCCI test scripts
#
# What is here is only what rOCCI needs: which server the tests talk to and on which
# port, where the credentials of the current backend are kept, which backends a run
# goes through, and how to ask for one of them to be switched.
#
# Everything generic - the output modes and the test_* verbs, the SYS_* binary
# names, check_binaries() and the rest - lives in tools/lib/ and arrives through
# testenv.sh, sourced below. It used to be duplicated in this file, and every rOCCI
# script also sourced LB's library through a symlink it created in the directory it
# was run from.
#
# Switching the backend is not here: it is a root operation and lives in
# rOCCI-switch-backend.sh, which setup.sh installs outside this checkout and names in
# sudoers. What is here is the call through sudo.
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
# server, the same port and the same switch helper. Everything below only fills in
# what is unset.
ROCCI_ENV_FILE=${ROCCI_ENV:-$(state_file rocci.env)}
if [ -r "$ROCCI_ENV_FILE" ]; then
	# shellcheck source=/dev/null
	source "$ROCCI_ENV_FILE"
fi

# The server the tests query. It answers on 11443 with the host certificate of this
# machine, which is what the packaged rOCCI Apache configuration does; ROCCI_SERVER
# and ROCCI_PORT are what setup.sh found and wrote.
ROCCI_SERVER=${ROCCI_SERVER:-$(hostname -f 2> /dev/null || hostname)}
ROCCI_PORT=${ROCCI_PORT:-11443}
ROCCI_URL=${ROCCI_URL:-https://$ROCCI_SERVER:$ROCCI_PORT}
export ROCCI_SERVER ROCCI_PORT ROCCI_URL

# Where the credentials of the backend currently selected are, written by the switch
# helper and owned by whoever runs the tests. It holds a password, so unlike the env
# file it is never put into a report.
ROCCI_INFO=${ROCCI_INFO:-$(state_file rocci-info.sh)}
export ROCCI_INFO

# The client the deployment test checks for.
OCCI_CLIENT=${OCCI_CLIENT:-occi}
export OCCI_CLIENT

# Which configuration the server is served from and which service has to be restarted
# when the backend changes. setup.sh found both and wrote them into the env file; the
# switch helper works them out on its own the same way, so what is lost without them
# is only the ability to say here what the testbed is.
ROCCI_CONFIG=${ROCCI_CONFIG:-}
ROCCI_SERVICE=${ROCCI_SERVICE:-}
export ROCCI_CONFIG ROCCI_SERVICE

# The installed helper that switches backends, and the backends a run goes through,
# as NAME:SECONDS_TO_WAIT_FOR_IT. 'dummy' waits for nothing because there is nothing
# to wait for; the OpenNebula versions are the ones the suite named, each needing a
# machine of that version registered in the service discovery.
ROCCI_TOGGLE=${ROCCI_TOGGLE:-/usr/libexec/glite-testsuites/rOCCI-switch-backend}
ROCCI_BACKENDS=${ROCCI_BACKENDS:-dummy:0 opennebula-4.12:1200 opennebula-4.10:120 opennebula-4.8:120 amazon:120}
export ROCCI_TOGGLE ROCCI_BACKENDS

# rocci_switch BACKEND [WAIT] - put the server on that backend.
#
# It goes through sudo to the one program setup.sh installed, rather than editing
# /etc and restarting Apache from here: the tests are run by an unprivileged user,
# and a sudoers rule for 'sed' and 'service' would be a root shell by another name.
# Returns what the helper returns: 0 the server is on that backend, 3 the backend is
# not available on this testbed, anything else is broken.
rocci_switch()
{
	local backend=$1
	local waiting=${2:-1800}
	local prog=${ROCCI_TOGGLE:-/usr/libexec/glite-testsuites/rOCCI-switch-backend}

	if [ ! -x "$prog" ]; then
		update_error "$prog is not installed - run rOCCI/tests/setup.sh as root"
		return $TEST_ERROR
	fi
	# The helper prints why it refused; it goes to the log the test is in.
	sudo -n "$prog" "$backend" "$waiting"
}
