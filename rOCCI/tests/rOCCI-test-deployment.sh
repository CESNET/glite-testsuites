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

# show help and usage
progname=`basename $0`
showHelp()
{
cat << EndHelpHeader
Script for basic testing of rOCCI deployment by listing categories.

Prerequisities:
   - rOCCI CLI installed
   - file /tmp/rocci-info.sh (rOCCI-test-helper-switch-backend.sh called)

Tests called:

    deployment presence

Returned values:
    Exit TEST_OK: Test Passed
    Exit TEST_ERROR: Test Failed
    Exit 2: Wrong Input

EndHelpHeader

	echo "Usage: $progname [OPTIONS]"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -o | --output 'file'   Redirect all output to the 'file' (stdout by default)."
	echo " -t | --text            Format output as plain ASCII text."
	echo " -c | --color           Format output as text with ANSI colours (autodetected by default)."
	echo " -x | --html            Format output as html."
}

# read common definitions and functions
COMMON=rOCCI-common.sh
if [ ! -r ${COMMON} ]; then
	printf "Common definitions '${COMMON}' missing!"
	exit 2
fi
source ${COMMON}

logfile=$$.tmp
flag=0
while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		"-o" | "--output") shift ; logfile=$1 flag=1 ;;
		"-t" | "--text")  setOutputASCII ;;
		"-c" | "--color") setOutputColor ;;
		"-x" | "--html")  setOutputHTML ;;
	esac
	shift
done

# redirecting all output to $logfile
touch $logfile
if [ ! -w $logfile ]; then
	echo "Cannot write to output file $logfile"
	exit $TEST_ERROR
fi

DEBUG=2

##
#  Starting the test
#####################

{
test_start


# check_binaries
printf "Testing if all binaries are available"
check_binaries $OCCI_CLIENT $SYS_CURL
if [ $? -gt 0 ]; then
	test_failed
else
	test_done
fi

# curl args
curl_args='--silent'
capath=''
for dir in '/etc/ssl/certs' '/etc/grid-security/certificates' '/tmp/test-certs.root/grid-security/certificates' '/tmp/test-certs.glite/grid-security/certificates'; do
	if [ -d ${dir} ]; then
		if [ -z "${capath}" ]; then
			capath="${dir}"
		else
			capath="${capath}:${dir}"
		fi
	fi
done
if [ -n "${capath}" ]; then
	curl_args="${curl_args} ${capath}"
fi

printf "Checking credentials"
if [ -f /tmp/rocci-info.sh ]; then
	source /tmp/rocci-info.sh
fi
if [ -n "${rocci_password}" ]; then
	test_done
else
	test_failed
fi

printf "Listing categories"
cat_file='/tmp/categories.txt'
${SYS_CURL} ${curl_args} -u ${rocci_user}:${rocci_password} -H 'Accept: text/plain' https://`hostname -f`:11443/-/ > ${cat_file}
if [ $? -eq 0 ]; then
	test_done
else
	test_failed
	echo "${SYS_CURL} ${curl_args} -u ${rocci_user}:XXXXXX -H 'Accept: text/plain' https://`hostname -f`:11443/-/"
	cat ${cat_file}
fi

printf "Checking body contains any categories"
grep -q '^Category:.*;scheme=".*"' ${cat_file}
if [ $? -eq 0 ]; then
	test_done
else
	test_failed
fi

printf "Checking body contains only categories"
grep -vq '^Category:.*;scheme=".*"' ${cat_file}
if [ $? -ne 0 ]; then
	test_done
else
	test_failed
fi

test_end
}
exit $TEST_OK
