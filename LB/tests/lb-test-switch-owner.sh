#!/bin/bash
#
# Copyright (c) Members of the EGEE Collaboration. 2004-2010.
# See http://www.eu-egee.org/partners/ for details on the copyright holders.
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
Script for testing correct interpretation of ChangeACL events

Prerequisities:
   - LB server, logger, interlogger
   - environment variables set:

     GLITE_WMS_QUERY_SERVER
     X509_USER_PROXY_BOB

Tests called:

    job registration
    sending a GrantOwnership event
    sending a TakeOwnership event
    quering and tagging the job using the Bob's certificate

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
COMMON=lb-common.sh
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

CONT="yes"
while [ "$CONT" = "yes" ]; do
	CONT="no"

	# check_binaries
	printf "Testing if all binaries are available"
	check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK $LBLOGEVENT $LBJOBREG
	if [ $? -gt 0 ]; then
		test_failed
		break
	fi
	test_done

	printf "Testing credentials"
	check_credentials
	if [ $? -ne 0 ]; then
		test_failed
		break
	fi
	if [ "$X509_USER_PROXY_BOB" = "" ]; then
		test_failed
		print_error "\$X509_USER_PROXY_BOB must be set"
		break
	fi
	check_credentials $X509_USER_PROXY_BOB
	if [ $? -ne 0 ]; then
		test_failed
		break
	fi
	test_done

	identity=`${GRIDPROXYINFO} -f $X509_USER_PROXY_BOB| ${SYS_GREP} -E "^identity" | ${SYS_SED} "s/identity\s*:\s//"`

	# Register job:
	printf "Registering testing job "
	jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
	if [ -z $jobid  ]; then
		test_failed
		print_error "Failed to register job"
		break
	fi
	test_done

	printf "Setting payload owner ..."
	$LBLOGEVENT -e GrantPayloadOwnership -s UserInterface --payload_owner "$identity" -j "$jobid" > /dev/null
	if [ $? -ne 0 ]; then
		test_skipped
		print_error "Failed to send GrantPayloadOwnership event, skipping the rest"
		break
	fi

	X509_USER_PROXY=$X509_USER_PROXY_BOB $LBLOGEVENT -e TakePayloadOwnership -s UserInterface -j "$jobid" > /dev/null
	if [ $? -ne 0 ]; then
		test_failed
		print_error "Sending GrantPayloadOwnership failed"
		break
	fi
	test_done

#	sleep 10

	printf "Testing acquired permissions"
	id=`X509_USER_PROXY=$X509_USER_PROXY_BOB $LBJOBSTATUS $jobid | grep "^payload_owner :" | sed 's/^payload_owner : //'`
	if [ $? -ne 0 ]; then
		test_failed
		print_error "Quering server failed"
		break
	fi
	if [ "$id" != "$identity" ]; then
		test_failed
		print_error "Payload owner not set in status"
		break
	fi

	X509_USER_PROXY=$X509_USER_PROXY_BOB $LBLOGEVENT -e UserTag -s Application -j $jobid --name "hokus" --value "pokus" > /dev/null
	if [ $? -ne 0 ]; then
		test_failed
		print_error "Sending UserTag failed"
		break
	fi
	
#	sleep 10

	res=`X509_USER_PROXY=$X509_USER_PROXY_BOB $LBJOBSTATUS $jobid 2>/dev/null`
	if [ $? -ne 0 ]; then
		test_failed
		print_error "Quering server failed"
		break
	fi
	echo $res | grep "hokus = \"pokus\"" > /dev/null
	if [ $? -ne 0 ]; then
		test_failed
		print_error "Adding UserTag not allowed"
		break
	fi

	test_done

	#Purge test job
	joblist=$$_jobs_to_purge.txt
	echo $jobid > ${joblist}
	try_purge ${joblist}
done

test_end
} &> $logfile

if [ $flag -ne 1 ]; then
 	cat $logfile
 	$SYS_RM $logfile
fi
exit $TEST_OK
