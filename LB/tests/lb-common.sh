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
# Definitions of functions and variables common to LB test scripts
#
#   ping_host() - basic network ping
#   check_binaries() - check for binary executables, calls check_exec()
#   check_socket() - TCPecho to host:port
#
# ------------------------------------------------------------------------------

# read common definitions and functions
TEST_COMMON=test-common.sh
if [ ! -r ${TEST_COMMON} ]; then
	printf "Common definitions '${TEST_COMMON}' not found!\n"
	exit 2	
fi
source ${TEST_COMMON}

ulimit -c unlimited

# define variables
GLITE_LB_LOCATION=${GLITE_LB_LOCATION:-$GLITE_LOCATION}
GLITE_LOCATION=${GLITE_LOCATION:-'/usr'}
SAME_SENSOR_HOME=${SAME_SENSOR_HOME:-.}
for dir in $GLITE_LOCATION $GLITE_LOCATION/lib64/glite-lb $GLITE_LOCATION/lib/glite-lb; do
	if test -d "$dir/examples"; then PATH="$dir/examples:$PATH"; fi
done
PATH="$GLITE_LOCATION/bin:$PATH"
export PATH

# LB binaries
LBLOGEVENT=glite-lb-logevent
LBJOBLOG=glite-lb-job_log
LBWSJOBLOG=glite-lb-ws_joblog
LBJOBREG=glite-lb-job_reg
LBUSERJOBS=glite-lb-user_jobs
LBJOBSTATUS=glite-lb-job_status
LBTHRJOBSTATUS=glite-lb-job_status_threaded
LBWSJOBSTATUS=glite-lb-ws_jobstat
LBWSGETVERSION=glite-lb-ws_getversion
LBPURGE=glite-lb-purge
LBCHANGEACL=glite-lb-change_acl
LBMON=glite-lb-lbmon
LBNOTIFY=glite-lb-notify
LBPURGE=glite-lb-purge
LBPARSEEFILE=glite-lb-parse_eventsfile
LB4AGUACTINFO=glite-lb-ws_lb4agu_GetActivityInfo
LB4AGUACTSTATUS=glite-lb-ws_lb4agu_GetActivityStatus
LBREGSANDBOX=glite-lb-register_sandbox
LBHISTORY=glite-lb-state_history
LBCMSCLIENT=glite-lb-cmsclient
LBQUERYEXT=glite-lb-query_ext
LBNOTIFKEEPER=glite-lb-notif-keeper
LBDUMP=glite-lb-dump
LBLOAD=glite-lb-load

LB_LOGD=glite-lb-logd 
LB_INTERLOGD=glite-lb-interlogd
LB_SERVER=glite-lb-bkserverd

LB_READY_SH=glite-lb-ready.sh
LB_RUNNING_SH=glite-lb-running.sh
LB_DONE_SH=glite-lb-done.sh
LB_CLEARED_SH=glite-lb-cleared.sh

LB_STATS=glite-lb-stats
LB_FROMTO=glite-lb-stats-duration-fromto

#general grid binaries
GRIDPROXYINFO=grid-proxy-info

# default LB ports
GLITE_LB_SERVER_PORT=${GLITE_LB_SERVER_PORT:-9000}
GLITE_LB_IL_SOCK=${GLITE_LB_IL_SOCK:-/tmp/interlogger.sock}
let GLITE_LB_SERVER_QPORT=${GLITE_LB_SERVER_PORT}+1
if [ -z "${GLITE_LB_SERVER_WPORT}" ]; then 
	let GLITE_LB_SERVER_WPORT=${GLITE_LB_SERVER_PORT}+3
fi

GLITE_LB_LOGGER_PORT=${GLITE_LB_LOGGER_PORT:-9002}

# default sockets
GLITE_WMS_LBPROXY_STORE_SOCK=${GLITE_WMS_LBPROXY_STORE_SOCK:-/tmp/lb_proxy_}

# other binaries
TEST_SOCKET=$SAME_SENSOR_HOME/tests/testSocket
SYS_LSOF=lsof
SYS_GREP=grep
SYS_SED=sed
SYS_PS=ps
SYS_PIDOF=pidof
SYS_MYSQLD=mysqld
SYS_MYSQLADMIN=mysqladmin
SYS_PING=ping
SYS_AWK=awk
SYS_ECHO=echo
SYS_DOMAINNAME=domainname
SYS_CURL=curl
SYS_RM="rm -f"
SYS_CHMOD=chmod
SYS_LDAPSEARCH=ldapsearch
SYS_CAT=cat
SYS_NL=nl
SYS_TAIL=tail
SYS_DATE=date
SYS_EXPR=expr
SYS_BC=bc
SYS_SCP=scp
SYS_TOUCH=touch
SYS_HOSTNAME=hostname
SYS_RPM=rpm
SYS_WC=wc
SYS_LS=ls
SYS_STAT=stat
SYS_DPKG_QUERY=dpkg-query
SYS_FIND=find

# not used at the moment
DEBUG=2

function check_credentials_and_generate_proxy()
{	
	check_credentials
	if [ $? != 0 ]; then
		if [ "$1" != "" ]; then
			PROXYLIFE=" --hours $1"
		else 
			PROXYLIFE=""
		fi
		source ./lb-generate-fake-proxy.sh $PROXYLIFE
		if [ $? != 0 ]; then
			test_failed
			print_error "Proxy not created - process failed"
			return 2
		fi
		check_credentials
		if [ $? != 0 ]; then
			test_failed
			print_error "Credentials still not passing check"
			return 2
		fi
	else
		test_done
	fi
	return 0
}

# ping host
function ping_host()
{
	if [ -z $1 ]; then
		set_error "No host to ping"
		return $TEST_ERROR
	fi
	PING_HOST=$1
	# XXX: there might be a better way to test the network reachability
	result=`${SYS_PING} -c 3 $PING_HOST 2>/dev/null | ${SYS_GREP} " 0% packet loss"| wc -l`
	if [ $result -gt 0 ]; then
		return $TEST_OK
	else 
		return $TEST_ERROR
	fi
}


# check the binaries
function check_exec()
{
	if [ -z $1 ]; then
		set_error "No binary to check"
		return $TEST_ERROR
	fi
	# XXX: maybe use bash's command type?
	local ret=`which $1 2> /dev/null`
	if [ -n "$ret" -a -x "$ret" ]; then
		return $TEST_OK
	else
		return $TEST_ERROR
	fi
}

function check_binaries()
{
# TODO: test only the binaries that are needed - it can differ in each test
	local ret=$TEST_OK
	for file in $@
	do	
		check_exec $file 
		if [ $? -gt 0 ]; then
			print_error "command $file not found"
			ret=$TEST_ERROR
		fi
	done
	return $ret
}

# check socket
function check_socket()
{
	if [ $# -lt 2 ]; then
		set_error "No host:port to check"
		return $TEST_ERROR
	fi
	$TEST_SOCKET $1 $2 2> $testerrfile
	if [ $? -eq 0 ];  then 
		return $TEST_OK
	else
		return $TEST_ERROR
	fi
}

# Check listener
# Arguments:
#  $1: program expected to listen on the given port
#  $2: TCP port to check
function check_listener()
{
	req_program=$1
	req_port=$2
        if [ -z $1 ]; then
                set_error "No program name entered"
                return $TEST_ERROR
        fi

	pid=`lsof -F p -i TCP:$req_port | sed "s/^p//"`
	if [ -z $pid ]; then
		return $TEST_ERROR
	fi
	program=`ps -p ${pid} -o args= | grep -E "[\/]*$req_program[ \t]*"`
	if [ -z "$program" ];  then 
		return $TEST_ERROR
	else
		return $TEST_OK
	fi
}


# Check socket listener
# Arguments:
#  $1: program expected to listen on the given socket
#  $2: socket to check
function check_socket_listener()
{
	req_program=$1
	req_socket=$2
        if [ -z $1 ]; then
                set_error "No program name entered"
                return $TEST_ERROR
        fi

	pid=`lsof -F p $req_socket | sed "s/^p//" | head -n 1`
	if [ -z $pid ]; then
		return $TEST_ERROR
	fi
	program=`ps -p ${pid} -o args= | grep -E "[\/]*$req_program[ \t]*"`
	if [ -z "$program" ];  then 
		return $TEST_ERROR
	else
		return $TEST_OK
	fi
}

#df /var/lib/mysql/ | tail -n 1 | awk '{ print $4 }'

function try_purge()
{
                        #Purge test job
                        joblist=$1

                        printf "Purging test job (Trying the best, result will not be tested)\n"

                        ${LBPURGE} -j ${joblist}

                        $SYS_RM ${joblist}
	
}

function test_args()
{
        echo $@
}

function check_credentials()
{
	my_GRIDPROXYINFO=${GRIDPROXYINFO}
	if [ "$1" != "" ]; then
		my_GRIDPROXYINFO="${GRIDPROXYINFO} -f $1"
	fi

	timeleft=`${my_GRIDPROXYINFO} 2>/dev/null | ${SYS_GREP} -E "^timeleft" | ${SYS_SED} "s/timeleft\s*:\s//"`
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

function check_srv_version()
{
        check_binaries $LBWSGETVERSION
        if [ $? -gt 0 ]; then
		return 2
        else
		servername=`echo ${GLITE_WMS_QUERY_SERVER} | ${SYS_SED} "s/:.*//"`
                wsglservver=`$LBWSGETVERSION -m ${servername}:${GLITE_LB_SERVER_WPORT} | $SYS_SED 's/^.*Server version:\s*//'`
                if [ "$wsglservver" = "" ]; then
               		return 2
                else
	
			SRVVER=`$SYS_ECHO $wsglservver | $SYS_GREP -o -E "^[0-9]+\.[0-9]+"`
			CHKVER=`$SYS_ECHO $2 | $SYS_GREP -o -E "^[0-9]*\.[0-9*]"`

			printf "Srv. version $SRVVER $1 $CHKVER? "
		        cresult=`$SYS_EXPR $SRVVER $1 $CHKVER`
	                if [ "$cresult" -eq "1" ]; then
				printf "yes "
				return 0
                	else
				printf "no "
				return 1
        	        fi
		fi
	fi
	return 0
}

function notif_wait() {
	timeout="$1"
	jobid="$2"
	f="$3"

	while ! $SYS_GREP ${jobid} "$f" > /dev/null 2>&1; do
		sleep 1
		printf "."
		timeout=$((timeout-1))
		if [ $timeout -le 0 ]; then
			printf "timeout"
			break;
		fi
	done
	sleep 1
	echo
	$SYS_GREP ${jobid} $$_notifications.txt > /dev/null
}

function check_rpmlint() {
	local pkg=''
	local out=''
	local ret=0

	printf "Packages compliance check output:${lf}"
	while test -n "$1"; do
		for pkg in `rpm -qa --queryformat '%{NAME} ' "$1"`; do
			printf "$pkg${lf}"
			out="`rpmlint $pkg`"
			if test -n "$is_html"; then
				echo "<pre>$out</pre>"
			else
				echo "$out"
			fi
			printf "${lf}\n"
			if echo $out | grep -i '^E:' >/dev/null; then
				ret=1
			fi
		done

		shift
	done

	return $ret
}

function check_lintian() {
	local dir=/tmp/lintian-check.$$
	local pkgs=''
	local pkg=''
	local src=''
	local out=''
	local ret=0

	rm -rf $dir
	mkdir $dir
	while test -n "$1"; do
		pkgs="$pkgs `dpkg-query -W "$1" 2>>$dir/query.log | cut -f1`
"
		shift
	done
	for pkg in $pkgs; do
		src=`dpkg-query -W -f '${Source}' $pkg 2>>$dir/query.log`
		if [ $? -eq 0 ]; then
			if [ -z "$src" ]; then src="$pkg"; fi
			pkgs="$pkgs
$src"
		fi
	done
	pkgs=`echo "$pkgs" | sort | uniq | sed 's/^ //'`

	if test -z "$pkgs"; then
		echo "No packages to check"
		return 0
	fi

	printf "Downloading packages..."
	(cd $dir; apt-get -d source $pkgs >$dir/download.log)
	if test $? -eq 0; then
		test_done
	else
		test_skipped
	fi

	echo "Packages compliance check output:"
	for pkg in $pkgs; do
		printf "$pkg:${lf}"
		out="`lintian $dir/${pkg}_*.dsc`"
		if test -n "$is_html"; then
			echo "<pre>$out</pre>"
		else
			echo "$out"
		fi
		printf "${lf}\n"
		if echo $out | grep -i '^E:' >/dev/null; then
			ret=1
		fi
	done

	rm -rf $dir
	return $ret
}

function check_build_help() {
	local progname=$1

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

function check_build() {
	local dir=${1:-'/tmp/reports'}
	local logs=`cd "$dir"; ls -1 *-build.log *.build 2>/dev/null`
	local ret=0
	local fatal=0

	printf "Build reports available"
	if [ -z "$logs" ]; then
		printf ": no";
		test_skipped
		return 0
	fi
	test_done

	for log in $logs; do
		printf "Checking $log"
		egrep 'warning: assignment makes pointer from integer without a cast' "$dir/$log" >/dev/null || \
		egrep 'warning: implicit declaration of function' "$dir/$log" >/dev/null
		fatal=$?
		if [ $fatal -eq 2 ]; then
			test_skipped
			continue
		fi
		# all relevant warning
		out="`grep 'warning: ' \"$dir/$log\" | egrep -v 'libtool|#ident|dpkg-[^:]+:'`"
		# filter-out warning considered OK but displayed
#echo "####$out####"
#echo "####`echo \"\$out\" | grep -v '^Makefile:'`####"
		if [ -n "`echo \"\$out\" | grep -v '^Makefile:'`" ]; then
			if [ $fatal -eq 0 ]; then
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
			if test -n "$is_html"; then
				printf "<pre>"
			else
				printf "${lf}"
			fi
			printf '%s' "$out"
			if test -n "$is_html"; then
				printf "</pre>\n"
			else
				printf "${lf}${lf}"
			fi
		fi
	done

	return $ret
}
