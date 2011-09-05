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
Script for testing stream notifications

Prerequisities:
   - LB server
   - Event logging chain
   - Notification delivery chain (notification interlogger)
   - environment variables set:

     GLITE_LOCATION
     GLITE_WMS_QUERY_SERVER
     GLITE_WMS_LOG_DESTINATION	
     GLITE_WMS_NOTIF_SERVER

Tests called:

    job registration
    logging events
    notification registration with stream flag
    receiving notifications

Returned values:
    Exit TEST_OK: Test Passed
    Exit TEST_ERROR: Test Failed
    Exit 2: Wrong Input/Other Error

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

while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
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

DEBUG=2
RETURN=2

##
#  Starting the test
#####################

test_start


# check_binaries
printf "Testing if all binaries are available"
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK
if [ $? -gt 0 ]; then
	test_failed
	exit $RETURN
else
	test_done
fi

printf "Testing credentials"

timeleft=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^timeleft" | ${SYS_SED} "s/timeleft\s*:\s//"`

while true; do
	if [ "$timeleft" = "" ]; then
	 	test_failed
	 	print_error "No credentials"
		break
	fi
	if [ "$timeleft" = "0:00:00" ]; then
		test_failed
		print_error "Credentials expired"
		break
	fi
	test_done

	RETURN=1

	check_srv_version '>=' "2.2"
	if [ $? -gt 0 ]; then
		printf "Capability not detected. This test will be"
		test_skipped
		break
	else
		test_done
	fi

	# Register job:
	printf "Registering job "
	jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application 2>&1 | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`

	if [ -z $jobid ]; then
		test_failed
		print_error "Failed to register job"
		break
	else
		printf "(${jobid}) "
		test_done
	fi

	# and log something:
	printf "Logging events resulting in DONE state"
	$LB_DONE_SH -j ${jobid} > /dev/null 2> /dev/null
	if [ $? -eq 0 ]; then
		test_done
	else
		test_failed
		print_error "Failed logging"
		break
	fi

	sleep 5

	# Register stream notification:
	printf "Registering notification "

	notifid=`${LBNOTIFY} new -j ${jobid} -f 256 | $SYS_GREP "notification ID" | ${SYS_AWK} '{ print $3 }'`

	if [ -z $notifid ]; then
		test_failed
		print_error "Failed to register notification"
		break
	fi
	printf "(${notifid}) "
	test_done

	#Start listening for notifications
	${LBNOTIFY} receive -i 10 ${notifid} > $$_notifications.txt &
	recpid=$!
	disown $recpid

	printf "Receiving the stream "
	notif_wait 10 ${jobid} $$_notifications.txt
	kill $recpid >/dev/null 2>&1

	$SYS_GREP ${jobid} $$_notifications.txt > /dev/null
	if [ $? = 0 ]; then
		printf "Notifications were delivered"
		test_done
	else
		printf "Notifications were NOT delivered"
		test_failed
		break
	fi

	RETURN=0
	break
done

$SYS_RM $$_notifications.txt

#Drop notification
if [ ! -z "${notifid}" ]; then
	printf "Dropping the test notification (${notifid})"
	dropresult=`${LBNOTIFY} drop ${notifid} 2>&1`
	if [ -z $dropresult ]; then
		test_done
	else
		test_failed
		print_error "Failed to drop notification ${dropresult}"
	fi
fi

#Purge test job
if [ ! -z "${jobid}" ]; then
	joblist=$$_jobs_to_purge.txt
	echo $jobid > ${joblist}
	try_purge ${joblist}
fi

test_end

exit $RETURN
