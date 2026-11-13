# shellcheck shell=bash
# shellcheck disable=SC2034,SC2059,SC2154
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
# Environment checks shared by every suite.
#
# The SYS_* variables indirect system binary names so that a distribution can be
# accommodated by overriding them (see docs/requirements.md for the known naming
# splits). They are all overridable from the environment; a suite may also set
# them in its own -common.sh.
#
# check_binaries() and friends report through $testerrfile and return
# $TEST_ERROR, they never exit - the test decides whether a miss is a failure, a
# skip or fatal. require_binaries() is the counterpart for setup scripts, which
# have no report line to close and must stop instead.
#
# SC2154 is disabled file-wide because $testerrfile, $lf, $is_html and
# $TEST_ERROR come from output.sh, which testenv.sh always sources first, and
# the linter only sees one file at a time. SC2059 is the printf of a format
# string held in a variable, which is what the reporting API is.
# ------------------------------------------------------------------------------

# System binaries, indirected. -----------------------------------------------

: "${SYS_APACHE:=httpd}"
: "${SYS_AWK:=awk}"
: "${SYS_BC:=bc}"
: "${SYS_CAT:=cat}"
: "${SYS_CHMOD:=chmod}"
: "${SYS_CURL:=curl}"
: "${SYS_DATE:=date}"
: "${SYS_DOMAINNAME:=domainname}"
: "${SYS_DPKG_QUERY:=dpkg-query}"
: "${SYS_ECHO:=echo}"
: "${SYS_EXPR:=expr}"
: "${SYS_FIND:=find}"
: "${SYS_GREP:=grep}"
: "${SYS_HEAD:=head}"
: "${SYS_HOSTNAME:=hostname}"
: "${SYS_LDAPSEARCH:=ldapsearch}"
: "${SYS_LS:=ls}"
: "${SYS_MYSQLADMIN:=mysqladmin}"
: "${SYS_MYSQLD:=mysqld}"
: "${SYS_NC:=nc}"
: "${SYS_NL:=nl}"
: "${SYS_PIDOF:=pidof}"
: "${SYS_PING:=ping}"
: "${SYS_PS:=ps}"
# The only multi-word name here, and the only one that cannot use the ${VAR:=}
# form: both ${VAR:='rm -f'} and ${VAR:=rm\ -f} keep the quoting characters in
# the value. The suites use $SYS_RM unquoted, so the value must be two words.
if [ -z "${SYS_RM:-}" ]; then
	SYS_RM='rm -f'
fi
: "${SYS_RPM:=rpm}"
: "${SYS_SCP:=scp}"
: "${SYS_SED:=sed}"
: "${SYS_SORT:=sort}"
: "${SYS_STAT:=stat}"
: "${SYS_TAIL:=tail}"
: "${SYS_TOUCH:=touch}"
: "${SYS_WC:=wc}"
export SYS_APACHE SYS_AWK SYS_BC SYS_CAT SYS_CHMOD SYS_CURL
export SYS_DATE SYS_DOMAINNAME SYS_DPKG_QUERY SYS_ECHO SYS_EXPR SYS_FIND
export SYS_GREP SYS_HEAD SYS_HOSTNAME SYS_LDAPSEARCH SYS_LS
export SYS_MYSQLADMIN SYS_MYSQLD SYS_NC SYS_NL SYS_PIDOF SYS_PING SYS_PS
export SYS_RM SYS_RPM SYS_SCP SYS_SED SYS_SORT SYS_STAT SYS_TAIL SYS_TOUCH SYS_WC

# Grid client binaries.
: "${GRIDPROXYINFO:=grid-proxy-info}"
export GRIDPROXYINFO

# The TCP probe helper built by LB/tests/Makefile. check_socket() falls back to
# "nc -z" when it has not been built, so it is not a hard requirement.
: "${TEST_SOCKET:=${TESTSUITE_HOME:-.}/LB/tests/testSocket}"
export TEST_SOCKET


# Is $1 an executable program resolvable through $PATH (or a path of its own)?
check_exec()
{
	if [ -z "${1:-}" ]; then
		set_error "No binary to check"
		return "$TEST_ERROR"
	fi
	# type -P searches $PATH only, so shell builtins and functions cannot
	# masquerade as the binaries the tests are about to run.
	local path
	path=$(type -P "$1" 2> /dev/null)
	if [ -n "$path" ] && [ -x "$path" ]; then
		return "$TEST_OK"
	else
		return "$TEST_ERROR"
	fi
}

# Check that every argument is an executable binary. The missing ones are
# accumulated and reported in a single print_error, because reporting each miss
# separately flushed - and thereby destroyed - the error detail that other
# checks in the same block had accumulated.
#
# Calling this with no arguments is a pass, not an error: tests legitimately
# pass through expansions that turn out to be empty.
check_binaries()
{
	local ret=$TEST_OK
	local file

	for file in "$@"; do
		if ! check_exec "$file"; then
			update_error "command $file not found"
			ret=$TEST_ERROR
		fi
	done

	if [ "$ret" -gt 0 ]; then
		print_error "not all needed binaries available"
	fi
	return "$ret"
}

# For setup scripts and drivers: refuse to start when a binary is missing and
# tell the tester where to read about it. Does not use the report verbs - there
# is no report line open here.
require_binaries()
{
	local missing=''
	local file

	for file in "$@"; do
		check_exec "$file" || missing="${missing} ${file}"
	done

	if [ -n "$missing" ]; then
		printf 'Missing required binaries:%s\n' "$missing" >&2
		printf 'See docs/requirements.md for how to install them.\n' >&2
		exit 1
	fi
}

# Reachability of a host.
ping_host()
{
	if [ -z "${1:-}" ]; then
		set_error "No host to ping"
		return "$TEST_ERROR"
	fi
	local result
	# XXX: there might be a better way to test the network reachability
	result=$($SYS_PING -c 3 "$1" 2>/dev/null | $SYS_GREP " 0% packet loss" | $SYS_WC -l)
	if [ "${result:-0}" -gt 0 ]; then
		return "$TEST_OK"
	else
		return "$TEST_ERROR"
	fi
}

# Can a TCP connection be established to host $1, port $2?
check_socket()
{
	if [ $# -lt 2 ]; then
		set_error "No host:port to check"
		return "$TEST_ERROR"
	fi
	if [ -x "$TEST_SOCKET" ]; then
		"$TEST_SOCKET" "$1" "$2" 2> "$testerrfile"
	else
		$SYS_NC -z "$1" "$2" 2> "$testerrfile"
	fi
}

# Which TCP ports and unix sockets are taken, asked of 'ss' (iproute2).
need_ss()
{
	if check_exec ss; then
		return 0
	fi
	set_error "cannot list the listening sockets - ss is not installed (iproute2)"
	return "$TEST_ERROR"
}

# Is anything listening on TCP port $1? Returns $TEST_OK when it is.
port_in_use()
{
	local port=${1:-}

	if [ -z "$port" ]; then
		set_error "No port to check"
		return "$TEST_ERROR"
	fi
	need_ss || return "$TEST_ERROR"
	# -n so that no port number is resolved to a service name and grepped for.
	ss -ltln 2> /dev/null | $SYS_GREP -qE "[:.]${port}([[:space:]]|$)"
}

# Is anything listening on the unix socket $1? Connecting to it to find out is not
# an option: that would disturb the service the socket belongs to.
unix_socket_in_use()
{
	local sock=${1:-}

	if [ -z "$sock" ]; then
		set_error "No socket to check"
		return "$TEST_ERROR"
	fi
	need_ss || return "$TEST_ERROR"
	ss -xln 2> /dev/null | $SYS_GREP -qF -- "$sock"
}

# Print the first TCP port from $1 to $2 that nothing is listening on; $TEST_ERROR
# and no output when the whole range is taken.
find_free_port()
{
	local low=${1:-11112}
	local high=${2:-$((low + 78))}
	local port=$low

	need_ss || return "$TEST_ERROR"
	while [ "$port" -le "$high" ]; do
		if ! port_in_use "$port"; then
			printf '%s\n' "$port"
			return 0
		fi
		port=$((port + 1))
	done
	set_error "no free TCP port in ${low}-${high}"
	return "$TEST_ERROR"
}

# Is $1 listening on TCP port $2?
# Arguments:
#  $1: program expected to listen on the given port
#  $2: TCP port to check
check_listener()
{
	local req_program=${1:-}
	local req_port=${2:-}
	local pid program

	if [ -z "${1:-}" ]; then
		set_error "No program name entered"
		return "$TEST_ERROR"
	fi
	if ! port_in_use "$req_port"; then
		return "$TEST_ERROR"
	fi
	# The port answers, which is what every caller of this function is asserting.
	# Whether the program named in $1 is the one answering is a second question, and
	# 'ss -p' can only ask it of a process whose command line this user may read: own
	# processes, or anything at all as root. When it cannot be read the caller is
	# told that rather than handed a failure it cannot do anything about - the suites
	# that care about the name check it separately (pidof, httpd -t -D DUMP_MODULES).
	# Where the name *can* be read it is still required, so a testbed with the wrong
	# service on the port is still caught.
	pid=$(ss -ltnp 2> /dev/null | $SYS_GREP -E "[:.]${req_port}([[:space:]]|$)" \
		| $SYS_SED -n 's/.*pid=\([0-9]*\).*/\1/p' | $SYS_HEAD -n 1)
	if [ -z "$pid" ]; then
		print_info "port ${req_port} answers but its owner is not readable by $(id -un) - the program name is not checked"
		return "$TEST_OK"
	fi
	program=$($SYS_PS -p "$pid" -o args= | $SYS_GREP -E "[/]*${req_program}[ 	]*")
	if [ -z "$program" ]; then
		set_error "port ${req_port} is held by PID ${pid}: $($SYS_PS -p "$pid" -o args= 2> /dev/null)"
		return "$TEST_ERROR"
	fi
	return "$TEST_OK"
}

# Is $1 listening on unix socket $2?
# Arguments:
#  $1: program expected to listen on the given socket
#  $2: socket to check
check_socket_listener()
{
	local req_program=${1:-}
	local req_socket=${2:-}
	local pid program

	if [ -z "${1:-}" ]; then
		set_error "No program name entered"
		return "$TEST_ERROR"
	fi
	if ! unix_socket_in_use "$req_socket"; then
		return "$TEST_ERROR"
	fi
	# As in check_listener(): the owning process is only name-checkable when this
	# user may read it, and the socket path itself is specific enough to be the
	# assertion when it is not.
	pid=$(ss -xlnp 2> /dev/null | $SYS_GREP -F -- "$req_socket" \
		| $SYS_SED -n 's/.*pid=\([0-9]*\).*/\1/p' | $SYS_HEAD -n 1)
	if [ -z "$pid" ]; then
		print_info "socket ${req_socket} is listening; its owner is not readable by $(id -un) - the program name is not checked"
		return "$TEST_OK"
	fi
	program=$($SYS_PS -p "$pid" -o args= | $SYS_GREP -E "[/]*${req_program}[ 	]*")
	if [ -z "$program" ]; then
		set_error "socket ${req_socket} is held by PID ${pid}: $($SYS_PS -p "$pid" -o args= 2> /dev/null)"
		return "$TEST_ERROR"
	fi
	return "$TEST_OK"
}

# ------------------------------------------------------------------------------
# Packaging and build compliance. These predate the split between setup.sh and
# run.sh: they audit an already installed (or mock-built) package set.
# ------------------------------------------------------------------------------

# rpmlint every package matching the given name patterns; fails on any E: line.
check_rpmlint()
{
	local pkg=''
	local out=''
	local ret=0

	printf "Packages compliance check output:${lf}"
	while test -n "${1:-}"; do
		for pkg in $($SYS_RPM -qa --queryformat '%{NAME} ' "$1"); do
			printf "%s${lf}" "$pkg"
			out=$(rpmlint "$pkg")
			if test -n "${is_html:-}"; then
				printf "<pre>"
				printf '%s' "$out" | htmlcat
				printf "</pre>"
			else
				echo "$out"
			fi
			printf "${lf}\n"
			# The word-splitting echo collapses the report into a single line,
			# so "^E:" can only ever match when the very first token starts with
			# E: - which rpmlint's "pkg: E: message" format never is. Kept as is:
			# matching per line would turn packaging checks that pass today into
			# failures, which is a decision to take on its own.
			# shellcheck disable=SC2086
			if echo $out | $SYS_GREP -i '^E:' > /dev/null; then
				ret=1
			fi
		done

		shift
	done

	return "$ret"
}

# lintian every package matching the given name patterns, pulling the sources
# down first because lintian reads the .dsc rather than the installed package.
# Debian family only.
check_lintian()
{
	local dir=/tmp/lintian-check.$$
	local pkgs=''
	local sources=''
	local pkg=''
	local src=''
	local out=''
	local ret=0

	rm -rf "$dir"
	mkdir "$dir"
	while test -n "${1:-}"; do
		pkgs="$pkgs
$($SYS_DPKG_QUERY -W "$1" 2>> "$dir/query.log" | cut -f1)"
		shift
	done
	# Source packages are what lintian actually reads. The list built while
	# walking the binary packages is deliberately not walked itself.
	for pkg in $pkgs; do
		# shellcheck disable=SC2016
		if src=$($SYS_DPKG_QUERY -W -f '${Source}' "$pkg" 2>> "$dir/query.log"); then
			if [ -z "$src" ]; then src="$pkg"; fi
			sources="${sources}
${src}"
		fi
	done
	pkgs=$(printf '%s\n%s\n' "$pkgs" "$sources" | $SYS_GREP -v '^$' | sort | uniq)

	if test -z "$pkgs"; then
		echo "No packages to check"
		rm -rf "$dir"
		return 0
	fi

	printf "Downloading packages..."
	# shellcheck disable=SC2086
	(cd "$dir" && apt-get -d source $pkgs > "$dir/download.log")
	if test $? -eq 0; then
		test_done
	else
		test_skipped
	fi

	echo "Packages compliance check output:"
	for pkg in $pkgs; do
		printf "%s:${lf}" "$pkg"
		out=$(lintian "$dir/${pkg}"_*.dsc)
		if test -n "${is_html:-}"; then
			printf "<pre>"
			printf '%s' "$out" | htmlcat
			printf "</pre>"
		else
			echo "$out"
		fi
		printf "${lf}\n"
		# Same collapsed-line matching as in check_rpmlint, for the same reason.
		# shellcheck disable=SC2086
		if echo $out | $SYS_GREP -i '^E:' > /dev/null; then
			ret=1
		fi
	done

	rm -rf "$dir"
	return "$ret"
}

# The --help text shared by the <suite>-test-packaging.sh scripts.
check_packaging_help()
{
	local progname=${1:-}

	cat << EndHelpHeader
Script producing errors and warnings due to packaging.

Prerequisities:
   - installed all tested packages
   - Scientific Linux: installed rpmlint
   - Debian: installed lintian

Tests called:

   called rpmlint or lintian on the packages

Returned values:
    Exit TEST_OK: Test Passed
    Exit TEST_ERROR: Test Failed
    Exit 2: Wrong Input

EndHelpHeader

	echo "Usage: $progname [OPTIONS]"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -t | --text            Format output as plain ASCII text."
	echo " -c | --color           Format output as text with ANSI colours (autodetected by default)."
	echo " -x | --html            Format output as html."
}

check_build_help()
{
	local progname=${1:-}

	cat << EndHelpHeader
Script for checking warnings in the build reports.

Prerequisities:
   - build reports copied into /tmp/reports
   - permited file names are *-build.log or *.build (output files from mock
     or pbuilder)

Returned values:
    Exit TEST_OK: Test Passed or Not Performed
    Exit TEST_ERROR: Test Failed
EndHelpHeader

	echo "Usage: $progname [OPTIONS]"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -o | --output 'file'   Redirect all output to the 'file' (stdout by default)."
	echo " -t | --text            Format output as plain ASCII text."
	echo " -c | --color           Format output as text with ANSI colours (autodetected by default)."
	echo " -x | --html            Format output as html."
}

# Scan mock/pbuilder logs in directory $1 for compiler warnings. Skips a log
# whose fatal patterns cannot be evaluated at all, fails when one of them is
# present alongside any other warning, and warns when only the other warnings
# are present.
check_build()
{
	local dir=${1:-/tmp/reports}
	local logs
	local ret=0
	local fatal=0
	local log out

	logs=$(cd "$dir" 2>/dev/null && ls -1 -- *-build.log *.build 2>/dev/null)

	printf "Build reports available"
	if [ -z "$logs" ]; then
		printf ": no"
		test_skipped
		return 0
	fi
	test_done

	for log in $logs; do
		printf "Checking %s" "$log"
		$SYS_GREP -E 'warning: assignment makes pointer from integer without a cast' "$dir/$log" > /dev/null || \
		$SYS_GREP -E 'warning: implicit declaration of function' "$dir/$log" > /dev/null || \
		$SYS_GREP -E 'warning: .* makes integer from pointer without a cast' "$dir/$log" > /dev/null || \
		$SYS_GREP -E 'warning: cast to pointer from integer of different size' "$dir/$log" > /dev/null || \
		$SYS_GREP -E 'warning: cast from pointer to integer of different size' "$dir/$log" > /dev/null
		# 0: a pattern that makes any other warning fatal is present
		# 1: none present, 2: the log could not be read at all
		fatal=$?
		if [ "$fatal" -eq 2 ]; then
			test_skipped
			continue
		fi
		# all relevant warning
		out=$($SYS_GREP 'warning: ' "$dir/$log" | $SYS_GREP -Ev 'libtool|#ident|dpkg-[^:]+:' | $SYS_GREP -v 'Could not canonicalize hostname')
		# filter-out warning considered OK but displayed
		if echo "$out" | $SYS_GREP -qv '^Makefile:'; then
			if [ "$fatal" -eq 0 ]; then
				test_failed
				print_error "fatal warnings found"
				ret=1
			else
				test_warning
			fi
		else
			test_done
		fi
		if [ -n "$out" ]; then
			if test -n "${is_html:-}"; then
				printf "<pre>"
				echo "$out" | htmlcat
				printf "</pre>\n"
			else
				printf "${lf}"
				printf '%s' "$out"
				printf "${lf}${lf}"
			fi
		fi
	done

	return $ret
}
