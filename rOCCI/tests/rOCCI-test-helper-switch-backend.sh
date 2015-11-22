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
Helper script for switching rOCCI backend. Not real test, but it may fail. In case of failure all tests after should be probably ignored.

The file /tmp/rocci-info.sh is created.

Prerequisities:
   - rOCCI server installed
   - Zookeeper Service Discovery Available (zookeeper server)
   - Zoosync client deployed

Tests called:

    for opennebula: look up in the Zookeeper Service Discovery
    switch the backend

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

TEST_RESULT=${TEST_OK}
logfile=$$.tmp
flag=0
default_backend='dummy'
default_wait='1200'
while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		"-o" | "--output") shift ; logfile=$1 flag=1 ;;
		"-t" | "--text")  setOutputASCII ;;
		"-c" | "--color") setOutputColor ;;
		"-x" | "--html")  setOutputHTML ;;
		*)
			if [ -z "${backend}" ]; then
				backend="${1}"
			elif [ -z "${waiting}" ]; then
				waiting="${1}"
			fi
			;;
	esac
	shift
done

if [ -z ${backend} ]; then
	backend=${default_backend}
fi

if [ -z ${waiting} ]; then
	waiting=${default_wait}
fi

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


printf "Switching rOCCI server backend to ${backend}"
rocci_switch_backend ${backend} ${waiting}
zoo_ret=$?
if [ ${zoo_ret} -gt 0 ]; then
	test_failed
	TEST_RESULT=${TEST_ERROR}
else
	test_done
fi

file='/tmp/rocci-info.sh'
if [ ${zoo_ret} -eq 0 ]; then
	rm -f ${file}
	touch ${file}
	cat >> ${file} <<EOF
one_host='${one_host}'
EOF

	if [ -n "${one_admin_user}" ]; then
		cat >> ${file} <<EOF
rocci_user='${one_admin_user}'
rocci_password='${one_admin_pwd}'
EOF
	elif  [ -n "${aws_id}" ]; then
		cat >> ${file} <<EOF
rocci_user='${aws_id}'
rocci_password='${aws_key}'
EOF
	else
		cat >> ${file} <<EOF
rocci_user='dummyuser'
rocci_password='dummypassword'
EOF
	fi
	chmod 0600 ${file}
fi

test_end
}
exit ${TEST_RESULT}
