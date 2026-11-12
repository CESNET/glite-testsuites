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
# Definitions of functions and variables common to the CANL-C test scripts
#
# What is here is only what is specific to CANL-C: the names of the CANL example
# programs the tests drive and of the certificate they drive them with, and the
# two resolvers that pick which files those names refer to.
#
# Everything generic - the output modes and the test_* verbs, the SYS_* binary
# names, check_binaries(), check_socket(), check_listener(), the packaging and
# build checkers and the credential helpers - lives in tools/lib/ and arrives
# through testenv.sh, sourced below.
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

# The test material, before any of the paths below is derived from it.
#
# $CANL_ENV is the file setup.sh wrote ($STATE_DIR/canl.env), which pins
# TEST_CERTS and the certificate paths. Everything here only fills in what is
# unset, so a tester working with a real proxy is not overridden and a test run
# by hand after 'source $TEST_CERTS/env.sh' behaves the same as through run.sh.
# The other suites get this from their driver; CANL-C needs it per test because
# its paths are derived below, at source time.
CANL_ENV_FILE=${CANL_ENV:-$(state_file canl.env)}
if [ -r "$CANL_ENV_FILE" ]; then
	# shellcheck source=/dev/null
	source "$CANL_ENV_FILE"
fi
credentials_env

# The programs the tests drive. emi-canl-proxy-init and emi-canl-delegation come
# with the CANL-C package under test; emi-canl-client and emi-canl-server are the
# two samples, which no package ships and which the Makefile next to this file
# builds from the examples/ directory of a CANL-C source tree:
#
#	make -C CANL-C/tests top_srcdir=/path/to/canl-c
#
# All four default to the bare name and are looked up on $PATH, so an installation
# that puts them anywhere on it needs nothing. run.sh says the same thing when one
# is missing.
EMI_CANL_CLIENT=${EMI_CANL_CLIENT:-emi-canl-client}
EMI_CANL_SERVER=${EMI_CANL_SERVER:-emi-canl-server}
EMI_CANL_PROXY_INIT=${EMI_CANL_PROXY_INIT:-emi-canl-proxy-init}
EMI_CANL_DELEGATION=${EMI_CANL_DELEGATION:-emi-canl-delegation}

OPENSSL=openssl

# The certificate the tests start their CANL server with.
#
# tools/generate-test-certs.sh generates a host certificate for this machine and
# 'make -C tools install' installs it as /etc/grid-security/host{cert,key}.pem.
# The copy that stays in the tester's own tree is the very same pair and, unlike
# /etc/grid-security/hostkey.pem, it can be read without being root - which is
# what lets run.sh run these tests as an unprivileged user. Set CANL_HOST_CERT
# and CANL_HOST_KEY (in $CANL_ENV, or in the environment) to drive the tests with
# the deployed pair instead; nothing in this suite asserts anything about which
# pair the server it starts uses.
if [ -z "${CANL_HOST_CERT:-}" ] || [ -z "${CANL_HOST_KEY:-}" ]; then
	CANL_HOST_DIR=${CANL_HOST_DIR:-${HOST_CERT_DIR:-$TEST_CERTS/grid-security}}
	# The deployed pair rather than the tester's own copy, if there is no
	# readable generated one.
	if [ ! -r "$CANL_HOST_DIR/hostkey.pem" ]; then
		CANL_HOST_DIR=/etc/grid-security
	fi
	CANL_HOST_CERT=${CANL_HOST_CERT:-$CANL_HOST_DIR/hostcert.pem}
	CANL_HOST_KEY=${CANL_HOST_KEY:-$CANL_HOST_DIR/hostkey.pem}
fi
export CANL_HOST_CERT CANL_HOST_KEY

# The client certificate canl-test-sha2.sh connects with: the generated one
# whose signature is SHA-512, which is what the test is about. Everything the
# generator writes is unencrypted ('.priv'), the CANL examples cannot be asked
# for a passphrase.
CANL_SHA2_CERT=${CANL_SHA2_CERT:-$TEST_CERTS/trusted-certs/trusted_clientsha512.cert}
CANL_SHA2_KEY=${CANL_SHA2_KEY:-$TEST_CERTS/trusted-certs/trusted_clientsha512.priv}
export CANL_SHA2_CERT CANL_SHA2_KEY

# Picks the server and client canl-test-{cs-openssl,sec-connection,ocsp,sha2}.sh
# drive. $1/$2 are the paths their -s and -k options pass; given both, those are
# used as they are, otherwise the names above are looked up.
#
# It opens the report line and leaves the verdict verb to the caller, which used
# to print a second "-TEST FAILED-" on top of this function's own. It does not
# download or build anything: the deleted get_canl_examples() wget'd four source
# files into the current directory and then asked make to compile them from
# ./examples/, a directory it never created (and then removed it), so the
# fallback could only ever fail. Makefile next to this file is the honest
# version of it and run.sh points at it.
get_canl_sc_binaries()
{
	if [ -n "${1:-}" ] && [ -n "${2:-}" ]; then
		EMI_CANL_SERVER=$1
		EMI_CANL_CLIENT=$2
	fi
	printf "Testing if binaries of canl examples are available"
	check_binaries "$EMI_CANL_SERVER" "$EMI_CANL_CLIENT"
}

# The same for the two examples canl-test-cert-handle.sh drives. Checking
# $EMI_CANL_DELEGATION as well is a fix, not a change of mind: the old version
# spelled the variable $EMI_CANL_DELEGATIOM, so the name expanded to nothing,
# was dropped from the argument list, and a missing emi-canl-delegation only
# surfaced twelve lines later as "command not found" in the test itself.
get_canl_proxy_binaries()
{
	if [ -n "${1:-}" ] && [ -n "${2:-}" ]; then
		EMI_CANL_PROXY_INIT=$1
		EMI_CANL_DELEGATION=$2
	fi
	printf "Testing if binary of canl_proxy_init is available"
	check_binaries "$EMI_CANL_PROXY_INIT" "$EMI_CANL_DELEGATION"
}
