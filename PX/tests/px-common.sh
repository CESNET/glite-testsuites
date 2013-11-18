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
TEST_COMMON=../../LB/tests/test-common.sh
if [ ! -r ${TEST_COMMON} ]; then
	printf "Common definitions '${TEST_COMMON}' not found!\n"
	exit 2	
fi
source ${TEST_COMMON}


# define variables
#GLITE_LOCATION=${GLITE_LOCATION:-'/usr'}
#SAME_SENSOR_HOME=${SAME_SENSOR_HOME:-.}
#PATH=$GLITE_LOCATION/bin:$GLITE_LOCATION/examples:$PATH
#export PATH

GRIDPROXYINFO=grid-proxy-info

# binaries
SYS_LSOF=lsof
SYS_GREP=grep
SYS_SED=sed
SYS_PS=ps
SYS_PIDOF=pidof
if test -f /usr/sbin/apache2; then
	SYS_APACHE=apache2
else
	SYS_APACHE=httpd
fi
if test -f /usr/sbin/apache2ctl; then
	SYS_APACHECTL=apache2ctl
else
	SYS_APACHECTL=apachectl
fi
SYS_PING=ping
SYS_AWK=awk
SYS_ECHO=echo
SYS_DOMAINNAME=domainname
SYS_CURL=curl
SYS_RM="rm -f"
SYS_CHMOD=chmod
SYS_CAT=cat
SYS_NL=nl
SYS_TAIL=tail
SYS_DATE=date
SYS_EXPR=expr
SYS_BC=bc
SYS_SCP=scp
SYS_NC=nc
SYS_CURL=curl
VOMSPROXYINFO=voms-proxy-info

# not used at the moment
DEBUG=2

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
			update_error "file $file not found"
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
	$SYS_NC -z $1 $2 > $testerrfile
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

	pid=`lsof -F p -i TCP:$req_port | sed "s/^p//" | head -n 1`
	if [ -z "$pid" ]; then
		return $TEST_ERROR
	fi
	program=`ps -p ${pid} -o args= | grep -E "[\/]*$req_program[ \t]*"`
	if [ -z "$program" ];  then 
		return $TEST_ERROR
	else
		return $TEST_OK
	fi
}

# make HTTP request using curl
# Arguments: Options to be passed to curl, at least the URL
# return http_code containing resulting code

function call_curl()
{
	http_code=`curl --cert ${X509_USER_PROXY} --key ${X509_USER_PROXY} \
		--capath ${X509_CERT_DIR} \
		--output /dev/null --silent --write-out '%{http_code}\n' \
		"$@"`
}
