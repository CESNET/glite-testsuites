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
curl_args="--silent -i"
capath=''
for dir in '/etc/ssl/certs' '/etc/grid-security/certificates'; do
	if [ -d ${dir} ]; then
		if [ -z "${capath}" ]; then
			capath="${dir}"
		else
			capath="${capath}:${dir}"
		fi
	fi
done
if [ -n "${capath}" ]; then
	curl_args="${curl_args} --capath ${capath}"
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
file_out='/tmp/categories-output.txt'
file_cat='/tmp/categories.txt'
${SYS_CURL} ${curl_args} -u ${rocci_user}:${rocci_password} -H 'Accept: text/plain' https://`hostname -f`:11443/-/ > ${file_out}
ret=$?

sed -i ${file_out} -e 's/\r//g'
awk '{if (ok) {print $0}} /^$/ {ok=1}' ${file_out} > ${file_cat}
http_code=`grep '^HTTP' ${file_out} | head -n 1 | sed -e 's,^HTTP/[^ ]\+\s\+\([0-9]\+\).*,\1,'`

if [ ${ret} -eq 0 -a x"${http_code}" = x"200" ]; then
	test_done
else
	if [ ${ret} -eq 0 ]; then
		printf "... HTTP code ${http_code}"
	else
		printf "... curl exit code ${ret}"
	fi
	test_failed
	echo "${SYS_CURL} ${curl_args} -u ${rocci_user}:XXXXXX -H 'Accept: text/plain' https://`hostname -f`:11443/-/"
	cat ${file_out}
	printf "${lf}"
fi


printf "Checking body contains any categories"
grep -q '^Category:.*;scheme=".*"' ${file_cat}
if [ $? -eq 0 ]; then
	test_done
else
	test_failed
fi


printf "Checking body contains only categories"
grep -vq '^Category:.*;scheme=".*"' ${file_cat}
if [ $? -ne 0 ]; then
	test_done
else
	test_failed
fi

test_end
}

exit $TEST_OK
