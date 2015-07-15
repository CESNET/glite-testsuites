#!/bin/bash
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
# Definitions of functions and variables common to LB test scripts
#
#   ping_host() - basic network ping
#   check_binaries() - check for binary executables, calls check_exec()
#   check_socket() - TCPecho to host:port
#
# ------------------------------------------------------------------------------

# read common definitions and functions
TEST_COMMON=./test-common.sh
if [ ! -r ${TEST_COMMON} ]; then
	if [ -r ../../LB/tests/${TEST_COMMON} ]; then
		ln -s ../../LB/tests/${TEST_COMMON}
	else
		printf "Common definitions '${TEST_COMMON}' not found!\n"
		exit 2	
	fi
fi
source ${TEST_COMMON}

ulimit -c unlimited

# define variables
#GLITE_LB_LOCATION=${GLITE_LB_LOCATION:-$GLITE_LOCATION}
#GLITE_LOCATION=${GLITE_LOCATION:-'/usr'}
#SAME_SENSOR_HOME=${SAME_SENSOR_HOME:-.}
#for dir in $GLITE_LOCATION $GLITE_LOCATION/lib64/glite-lb $GLITE_LOCATION/lib/glite-lb; do
#	if test -d "$dir/examples"; then PATH="$dir/examples:$PATH"; fi
#done
#PATH="$GLITE_LOCATION/bin:$PATH"
#export PATH

#general grid binaries
GRIDPROXYINFO=grid-proxy-info
#voms binaries
VOMSPROXYFAKE=voms-proxy-fake
OCCI_CLIENT=occi

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
OPENSSL=openssl

#generate proxy shell script file
GEN_PROXY=./canl-generate-fake-proxy.sh

# $1 - proxy init binary
# $2 - proxy delegation

#function check_credentials_and_generate_proxy()
#{	
#	check_credentials
#	if [ $? != 0 ]; then
#		if [ "$1" != "" ]; then
#			PROXYLIFE=" --hours $1"
#		else 
#			PROXYLIFE=""
#		fi
#		$GEN_PROXY $PROXYLIFE
#		if [ $? != 0 ]; then
#			print_error "Proxy not created - process failed"
#			return 2
#		fi
#		check_credentials
#		if [ $? != 0 ]; then
#			print_error "Credentials still not passing check"
#			return 2
#		fi
#	fi
#	return 0
#}

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
			print_error "$file not found"
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


#
# wait for opennebula in service discovery if needed
#
# $1 ... backend
# $2 ... waiting time
#
function zoosync_get_info()
{
	local backend_full=$1
	local waiting=${2:-'1800'}

	local version=${backend_full#'opennebula-'}
	local name="SERVICE_OPENNEBULA_${version//\./_}"
	local tagname_rocci="${name}_TAG__ROCCI"
	local tagname_oneadmin="${name}_TAG__ONEADMIN"

	if [ ! -f /etc/zoosyncrc ]; then
		printf "... Zoosync not configured"
		return 1
	fi

	eval `zoosync --service "${backend_full}" --wait ${waiting} wait`
	if [ $? -ne 0 -o -z "${SERVICES}" ]; then
		printf "... service ${backend_full} not found in Zookeeper"
		return 1
	fi
	eval one_host=\${${name}}

	eval `zoosync --service "${backend_full}" --hostname "${one_host}" read-tag _rocci _oneadmin`
	if [ $? -ne 0 ]; then
		printf "... credentials of ${backend_full} not found in Zookeeper"
		return 1
	fi
	eval one_rocci_pwd=\${${tagname_rocci}}
	eval one_admin_pwd=\${${tagname_oneadmin}}
	if [ -z "${one_rocci_pwd}" -o -z "${one_admin_pwd}" ]; then
		printf "... credentials of ${backend_full} not found in Zookeeper"
		return 1
	fi

	return 0
}


#
# 1) wait for opennebula in service discovery if needed
# 2) switch rOCCI server backend
#
# $1 ... backend
# $2 ... waiting time
#
function rocci_switch_backend()
{
	local backend_full=$1
	local waiting=${2:-'1800'}

	local conf='/etc/apache2/sites-available/occi-ssl'
	local service='apache2'

	if [ ! -f ${conf} ]; then
		conf='/etc/httpd/conf.d/occi-ssl.conf'
		service='httpd'
	fi
	if [ ! -f ${conf} ]; then
		printf "... Apache rOCCI config file not found"
		exit 1
	fi

	case ${backend_full} in
	opennebula*)
		backend='opennebula'

		zoosync_get_info ${backend_full} ${waiting} || return $?
		#echo "one: ${one_host}, rocci pwd: ${one_rocci_pwd}"

		sed -i ${conf} \
			-e "s/^\(\s*SetEnv\s\+ROCCI_SERVER_ONE_USER\s\+\).*/\1rocci/" \
			-e "s/^\(\s*SetEnv\s\+ROCCI_SERVER_ONE_PASSWD\s\+\).*/\1${one_rocci_pwd}/" \
			-e "s,^\(\s*SetEnv\s\+ROCCI_SERVER_ONE_XMLRPC\s\+\).*,\1http://${one_host}:2633/RPC2,"
	;;
	dummy)
		backend='dummy'
	;;
	*)
		printf "... unknown rOCCI backend '${backend}'"
		return 1
	;;
	esac

	sed -i ${conf} \
		-e "s/^\(\s*SetEnv\s\+ROCCI_SERVER_BACKEND\s\+\).*/\1${backend}/"

	service ${service} restart >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		printf "... restarting of '${service}' failed"
		exit 1
	fi
}
