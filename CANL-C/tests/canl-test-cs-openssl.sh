#!/bin/bash
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

# show help and usage
progname=`basename $0`
showHelp()
{
cat << EndHelpHeader
script for testing canl secured connection API using openssl server & client

Prerequisities: acces rights to host certificate file, proxy cert. file and appropriate key files.
Tests called:

    check_binaries

Returned values:
    Exit TEST_OK: Test Passed
    Exit TEST_ERROR: Test Failed
    Exit 2: Wrong Input

EndHelpHeader

	echo "Usage: $progname [OPTIONS]"
	echo "Options:"
	echo " -h | --help            Show this help message."
#	echo " -o | --output 'file'   Redirect all output to the 'file' (stdout by default)."
	echo " -t | --text            Format output as plain ASCII text."
	echo " -c | --color           Format output as text with ANSI colours (autodetected by default)."

	echo " -x | --html            Format output as html."
	echo " -s | --srvbin          Canl sample server file path"
	echo " -k | --clibin          Canl sample client file path"
}

# read common definitions and functions
COMMON=canl-common.sh
if [ ! -r ${COMMON} ]; then
	printf "Common definitions '${COMMON}' missing!"
	exit 2
fi
source ${COMMON}

#logfile=$$.tmp
#flag=0
srvbin=""
clibin=""
server_host=`hostname -A 2> /dev/null || hostname -f 2> /dev/null`
while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
#		"-o" | "--output") shift ; logfile=$1 flag=1 ;;
		"-s" | "--srvbin") shift ; srvbin=$1 ;;
		"-k" | "--clibin") shift ; clibin=$1 ;;
		"-t" | "--text")  setOutputASCII ;;
		"-c" | "--color") setOutputColor ;;
		"-x" | "--html")  setOutputHTML ;;
	esac
	shift
done

# redirecting all output to $logfile
#touch $logfile
#if [ ! -w $logfile ]; then
#	echo "Cannot write to output file $logfile"
#	exit $TEST_ERROR
#fi

##
#  Starting the tests
#####################

{
test_start
# check canl binaries
get_canl_sc_binaries $srvbin $clibin
if [ $? -ne 0 ]; then
	test_failed
	test_end
	exit $TEST_ERROR
else
	test_done
fi

# check_binaries
printf "Testing if all binaries are available"
check_binaries $EMI_CANL_SERVER $EMI_CANL_CLIENT \
	$VOMSPROXYFAKE $GRIDPROXYINFO $SYS_GREP \
	$SYS_SED $SYS_AWK $OPENSSL
if [ $? -gt 0 ]; then
	test_failed
else
	test_done
fi

printf "Testing credentials"
check_credentials_and_generate_proxy
if [ $? -gt 0 ]; then
	test_failed
	test_end
	exit 2
else
	test_done
fi

printf "Starting openssl server \n"
#find some unused port first
nu_port=11112
max_port=11190
${SYS_LSOF} -i :${nu_port}
while [ $? -eq 0 -a ${nu_port} -lt ${max_port} ]
do
        nu_port=$((nu_port+1))
        ${SYS_LSOF} -i :${nu_port}
done

if [ ${nu_port} -eq ${max_port} ]; then
        print_error "No port available"
        test_failed
	test_end
	exit 2
fi

pipe_srv=/tmp/canl_ossl_srv_pipe.$$

if [[ ! -p $pipe_srv ]]; then
    mkfifo $pipe_srv
fi

#then start server
cat $pipe_srv | ${OPENSSL} s_server -key /etc/grid-security/hostkey.pem \
-cert /etc/grid-security/hostcert.pem -quiet -accept "${nu_port}" &
last_pid=$!
lp_running=`${SYS_PS} | ${SYS_GREP} -E "${last_pid}" 2> /dev/null`
if [ -n "$lp_running" ]; then
	test_done
else
	test_failed
	test_end
	exit 2
fi

client_file="/tmp/client_file.$$"
if [[ -r $client_file ]]; then
    rm -rf $client_file
fi

#proxy_cert=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^path" | ${SYS_SED} "s/path\s*:\s//"`
printf "CANL client: connecting to openssl server\n"
${EMI_CANL_CLIENT} -s "${server_host}" -p "${nu_port}" &> $client_file &
#	-c ${proxy_cert} -k ${proxy_cert}

#give canl_client time to send his message first
sleep 9
msg_to_send_cli="hello,TM from ossl server"

echo "${msg_to_send_cli}" > $pipe_srv

t=20
found=""
is=0
while test $t -gt 0 && kill -0 ${last_pid} 2>/dev/null; do 
	sleep 0.5
	found=`${SYS_GREP} "${msg_to_send_cli}" "${client_file}"`
	if [ -n "$found" ]; then
		is=1
		break
	fi
	t=$((t-1))
done

if test "$is" -eq 0;then
	test_failed
else
	test_done
fi

kill ${last_pid} &> /dev/null

#find some unused port first
nu_port_2=11122
max_port=11190
${SYS_LSOF} -i :${nu_port_2}
while [ $? -eq 0 -a ${nu_port_2} -lt ${max_port} ]
do
        nu_port=$((nu_port_2+1))
        ${SYS_LSOF} -i :${nu_port_2}
done

if [ ${nu_port_2} -eq ${max_port} ]; then
        print_error "No port available"
        test_failed
	test_end
	exit 2
fi

server_file="/tmp/server_file.$$"
if [[ -r $server_file ]]; then
    rm -rf $server_file
fi

printf "Starting canl sample server \n"
${EMI_CANL_SERVER} -k /etc/grid-security/hostkey.pem \
	-c /etc/grid-security/hostcert.pem -p "${nu_port_2}" &> "$server_file" & 
last_pid=$!
lp_running=`${SYS_PS} | ${SYS_GREP} -E "${last_pid}" 2> /dev/null`
if [ -n "$lp_running" ]; then
	test_done
else
	test_failed
	test_end
	exit 2
fi

pipe=/tmp/canl_ossl_cli_pipe.$$

if [[ ! -p $pipe ]]; then
    mkfifo $pipe
fi

printf "Openssl client: connect to CANL sample server \n"
cat $pipe | ${OPENSSL} s_client -quiet -connect "${server_host}:${nu_port_2}" &
ssl_pid=$!

msg_to_send="hello,TM from canl server"

echo "${msg_to_send}" > $pipe

t=20
found=""
is=0
while test $t -gt 0 && kill -0 ${ssl_pid} 2>/dev/null; do 
	sleep 0.5
	found=`${SYS_GREP} "${msg_to_send}" "${server_file}"`
	if [ -n "$found" ]; then
		is=1
		break
	fi
	t=$((t-1))
done

if test "$is" -eq 0;then
	test_failed
else
	test_done
fi

rm -rf $pipe
rm -rf $pipe_srv
rm -rf $server_file
rm -rf $client_file

#if test "$t" -eq 0; then
#	kill -9 ${ssl_pid} && echo "OpenSSL process killed."
#fi

kill ${ssl_pid} &> /dev/null
kill ${last_pid} &> /dev/null

test_end
}
#} &> $logfile

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK
