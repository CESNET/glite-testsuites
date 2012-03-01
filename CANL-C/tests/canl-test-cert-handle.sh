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
script for simulating grid-proxy-init command (make new proxy cert.)
Prerequisities: 
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
	echo " -i | --init     	      Proxy init sample binary file"
	echo " -d | --deleg 	      Proxy delegation sample binary file"
	echo " -o | --origin          Certificate to generate proxy from"
	echo " -k | --key             Key to sign new proxy with"
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
proxy_bin=""
deleg_bin=""
old_cert=""
old_key=""
while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
#		"-o" | "--output") shift ; logfile=$1 flag=1 ;;
		"-i" | "--init") shift ; proxy_bin=$1 ;;
		"-d" | "--deleg") shift ; deleg_bin=$1 ;;
		"-o" | "--origin") shift ; old_cert=$1 ;;
		"-k" | "--key") shift ; old_key=$1 ;;
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
if [ -n "$old_key" -a -n "$old_cert" ]; then
echo ""
else
	print_error "key and certificate not specified"
	test_failed
	exit $TEST_ERROR
fi

# check canl binaries
get_canl_proxy_binaries $proxy_bin $deleg_bin
if [ $? -ne 0 ]; then
	test_failed
	test_end
	exit $TEST_ERROR
else
	test_done
fi

# check_binaries
printf "Testing if all binaries are available"
check_binaries $EMI_CANL_PROXY_INIT \
	$VOMSPROXYFAKE $GRIDPROXYINFO $SYS_GREP \
	$SYS_SED $SYS_AWK $OPENSSL
if [ $? -gt 0 ]; then
	test_failed
	test_end
	exit $TEST_ERROR
else
	test_done
fi

printf "Generating new proxy certificate \n"
$EMI_CANL_PROXY_INIT -c "$old_cert" -k "$old_key" -l 68400 -b 1024
if [ $? -ne 0 ]; then
	test_failed
else
	test_done
fi

printf "Simulating cert. delegation \n"
$EMI_CANL_DELEGATION -c "$old_cert" -k "$old_key" -l 68400 -b 1024
if [ $? -ne 0 ]; then
	test_failed
else
	test_done
fi

test_end
}
#} &> $logfile

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK
