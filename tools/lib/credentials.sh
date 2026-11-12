# shellcheck shell=bash
# shellcheck disable=SC2119,SC2120,SC2154
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
# Credential handling.
#
# The test credentials come from tools/ (make -C tools). Nothing in here ever
# generates a certificate: the drivers call credentials_env to point the process
# at the material and require_credentials to stop with the exact command when it
# is missing. Tests call check_credentials (reports and returns) or
# need_credentials (also closes the report line and says what to run).
#
# voms_lsc_install is the other thing here: the /etc/grid-security/vomsdir trust
# files that say which VOMS server an attribute may come from, which two of the
# setup scripts have to write and no test should.
#
# Additional identities (make -C tools EXTRA=N) live in the tree as
# $TEST_CERTS/trusted-certs/trusted_client01..NN and, with a VO, as
# $TEST_CERTS/home/voms-<VO>-clientNN.pem - tools/ neither names nor publishes
# them. This library is what decides that trusted_client01's proxy is the one a
# test acting as somebody else should use, under X509_USER_PROXY_BOB; a test
# wanting another of the extras names its own file.
#
# SC2119/SC2120: check_credentials takes an optional proxy file - the drivers
# call it bare, the test scripts call it with one, and shellcheck sees one file
# at a time. SC2154: $GRIDPROXYINFO and the $SYS_* names come from checks.sh,
# which testenv.sh sources before this file.
# ------------------------------------------------------------------------------

# Where tools/generate-test-certs.sh put the tree. Override with TEST_CERTS.
: "${TEST_CERTS:=/tmp/certs}"
export TEST_CERTS

# The CA certificate and CRL directory, under the name the legacy tests and the
# grid-mapfile recipes knew it by. Defaulted here rather than only by
# credentials_env() so that a script naming $TRUSTED_CERTS without having called
# it - which is what the deleted fake-proxy script used to be consumed for, its
# output grepped for exactly this line - sees a path instead of nothing.
: "${TRUSTED_CERTS:=$TEST_CERTS/trusted-certs}"
export TRUSTED_CERTS

# Does a (valid, non-expired) credential exist? With an argument, that file;
# otherwise the default proxy. Prints the reason on failure and returns 1 - it
# deliberately does not close the report line, the caller decides whether an
# absent credential is a failure or a skip.
check_credentials()
{
	local my_GRIDPROXYINFO=$GRIDPROXYINFO
	local timeleft

	if [ "${1:-}" != "" ]; then
		my_GRIDPROXYINFO="$GRIDPROXYINFO -f $1"
	fi

	timeleft=$($my_GRIDPROXYINFO 2>/dev/null | $SYS_GREP -E "^timeleft" | $SYS_SED "s/timeleft\s*:\s//")
	if [ "$timeleft" = "" ]; then
		printf "... No credentials... "
		return 1
	fi
	if [ "$timeleft" = "0:00:00" ]; then
		printf "... Credentials expired... "
		return 1
	fi
	return 0
}

# Point this process at the generated test credentials.
#
# The env.sh that the generator writes is the source of truth for the
# certificate paths. What is added here is only defaulted, never forced, so a
# tester working with a real proxy is not overridden.
credentials_env()
{
	local dir=${1:-$TEST_CERTS}
	local bob

	if [ -r "$dir/env.sh" ]; then
		# shellcheck source=/dev/null
		source "$dir/env.sh"
	else
		export X509_CERT_DIR="$dir/grid-security/certificates"
		export X509_USER_CERT="$dir/home/usercert.pem"
		export X509_USER_KEY="$dir/home/userkey.pem"
		export X509_VOMS_DIR="$dir/grid-security/vomsdir"
	fi

	export TRUSTED_CERTS="$dir/trusted-certs"
	export HOST_CERT_DIR="$dir/grid-security"
	: "${X509_USER_PROXY:=/tmp/x509up_u$(id -u)}"
	export X509_USER_PROXY
	# The identity a test acts as when it needs somebody who is not the tester:
	# the first of the additional clients. Its file name carries the VO it was
	# faked with, which the identity does not care about, so take whichever one
	# the tree has. Nothing else points at these, and unlike $X509_USER_PROXY
	# there is no conventional location, so this is where that is decided.
	if [ -z "${X509_USER_PROXY_BOB:-}" ]; then
		for bob in "$dir"/home/voms-*-client01.pem; do
			[ -e "$bob" ] && X509_USER_PROXY_BOB=$bob && break
		done
	fi
	export X509_USER_PROXY_BOB
}

# The form a test script calls at the point where it is about to use a proxy.
# It closes the report line the way check_credentials_and_generate_proxy used to,
# but it never generates anything: inventing credentials in the middle of a run
# hid the fact that none were configured, and turned "the testbed has no
# credentials" into a passing test. Prints why and returns non-zero, so that a
# test which cannot do anything without a proxy can stop instead of running on
# and reporting noise:
#
#     printf "Testing credentials"
#     need_credentials || { test_end; RET=2; break; }
#
need_credentials()
{
	if check_credentials "${1:-}"; then
		test_done
		return 0
	fi
	test_failed
	print_error "No usable credentials - generate them with 'make -C tools' and install them as root with 'make -C tools install' (docs/requirements.md)"
	return 2
}

# credentials_dn [CERTFILE] - the subject of a certificate as the grid middleware
# writes DNs: one line, slash separated, '/C=UG/L=Tropic/.../CN=somebody'.
#
# 'openssl x509 -noout -subject' without -nameopt prints whatever the OpenSSL it is
# runs on considers readable, and that changed: 1.0.x gave the slash form, 3.x gives
# 'C=UG, L=Tropic, ..., CN=somebody'. The tests that write a DN somewhere the
# middleware has to recognise it - a GridSite .gacl entry, a grid-mapfile line, a
# MyProxy server DN - compare text, so on a current box the plain form matches
# nothing and every 'with gacl' check answers 403 for a correctly configured
# service. compat asks for the form the middleware itself uses, on every version.
credentials_dn()
{
	local file=${1:-${X509_USER_CERT:-}}

	if [ -z "$file" ]; then
		printf 'credentials_dn: no certificate to read (set X509_USER_CERT or pass a file)\n' >&2
		return 1
	fi
	if [ ! -r "$file" ]; then
		printf 'credentials_dn: cannot read %s\n' "$file" >&2
		return 1
	fi
	openssl x509 -noout -subject -nameopt compat -in "$file" 2> /dev/null | sed -e 's/^subject= *//'
}

# voms_lsc_install [-c CApath] [-d VOMSDIR] - write the VOMS trust files.
#
# One .lsc file per entry in /etc/vomses, holding the DN of the VOMS host and the DN
# of the CA that signed its certificate. Without them a service ignores the VOMS
# extensions in a proxy completely, so a test that checks what mod_gridsite or the
# LB makes of an attribute is checking nothing.
#
# It is setup's job and not a test's: reading the chain needs network access and no
# decision, and doing it once here means the tests read something correct. Used by
# the GridSite and PX setup scripts, which is why it lives here and not in one of
# them. Prints one line per file written or skipped; returns 0 when it wrote at
# least one. Run as root - the target directory belongs to root.
voms_lsc_install()
{
	local capath=/etc/grid-security/certificates
	local vomsdir=/etc/grid-security/vomsdir
	local chain dn ca written=0 f host port vo

	while [ $# -gt 0 ]; do
		case $1 in
			'-c') shift; capath=${1:-$capath} ;;
			'-d') shift; vomsdir=${1:-$vomsdir} ;;
			*) printf 'voms_lsc_install: unknown argument %s\n' "$1" >&2; return 2 ;;
		esac
		shift
	done

	chain=$(mktemp "${TMPDIR:-/tmp}/voms-chain.XXXXXX") || return 1
	for f in /etc/vomses/*; do
		[ -f "$f" ] || continue
		# A vomses line is: "VO" "host" "port" "server DN" "service name", quoted.
		read -r vo host port _ < "$f" || continue
		vo=${vo//\"/}
		host=${host//\"/}
		port=${port//\"/}
		if [ -z "$host" ] || [ -z "$port" ]; then
			printf '%s: not a host and a port\n' "$f"
			continue
		fi
		openssl s_client -connect "$host:$port" -CApath "$capath" 2>&1 \
			| grep '^depth' | sed 's/^depth=//' | sort -r -n > "$chain"
		# Since RHEL6/SL6 openssl separates the DN with ", " and pads '=' with
		# spaces, and does not start the DN with a '/'.
		sed -i -r \
			-e 's#, #/#g' \
			-e 's#\s*=\s*#=#g' \
			-e 's#^([0-9]+\s+)([^ /])#\1/\2#' \
			"$chain"
		dn=$(tail -n 1 "$chain" | sed -r 's/^[0-9]+\s+//')
		ca=$(grep -E '^1[ \t]' "$chain" | sed -r 's/^[0-9]+\s+//')
		if [ -z "$dn" ] || [ -z "$ca" ]; then
			printf '%s: could not read the certificate chain of %s:%s\n' "$f" "$host" "$port"
			continue
		fi
		install -d -m 0755 "$vomsdir/$vo" || return 1
		printf '%s\n%s\n' "$dn" "$ca" > "$vomsdir/$vo/$host.lsc" || return 1
		printf '%s\n' "$vomsdir/$vo/$host.lsc"
		written=$((written + 1))
	done
	rm -f -- "$chain"

	[ "$written" -gt 0 ]
}

# Preflight for run.sh and setup.sh: refuse to start a run that can only fail.
# This is what replaced the old habit of generating credentials on the fly -
# silently inventing credentials hid the fact that none were configured.
require_credentials()
{
	local uid
	uid=$(id -u)

	if check_credentials; then
		return 0
	fi

	printf 'No usable credentials found.\n\n' >&2
	printf 'Generate them as the tester user:\n' >&2
	printf '    make -C %s CERTS=%s\n' "${TESTSUITE_HOME:-tools}" "$TEST_CERTS" >&2
	printf '\nand install the trust anchors as root:\n' >&2
	printf '    make -C %s install\n\n' "${TESTSUITE_HOME:-tools}" >&2
	printf 'Checked X509_USER_PROXY=%s (uid %s)\n' "${X509_USER_PROXY:-<unset>}" "$uid" >&2
	exit 2
}
