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
Script for testing notification delivery

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
    notification registration
    logging events
    receiving notifications

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
#touch $logfile
#if [ ! -w $logfile ]; then
#	echo "Cannot write to output file $logfile"
#	exit $TEST_ERROR
#fi

DEBUG=2

##
#  Starting the test
#####################

{
test_start


# check_binaries
printf "Testing if all binaries are available"
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK
if [ $? -gt 0 ]; then
	test_failed
else
	test_done
fi

printf "Testing credentials"

timeleft=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^timeleft" | ${SYS_SED} "s/timeleft\s*:\s//"`

if [ "$timeleft" = "" ]; then
        test_failed
        print_error "No credentials"
else
        if [ "$timeleft" = "0:00:00" ]; then
                test_failed
                print_error "Credentials expired"
        else
                test_done


		# Register job:
		printf "Registering testing job "
		jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application 2>&1 | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`

		if [ -z $jobid ]; then
			test_failed
			print_error "Failed to register job"
		else
			printf "(${jobid}) "
			test_done
		fi

		# Register notification:
		printf "Registering notification "

		notifid=`${LBNOTIFY} new -j ${jobid} | $SYS_GREP "notification ID" | ${SYS_AWK} '{ print $3 }'`

		if [ -z $notifid ]; then
			test_failed
			print_error "Failed to register notification"
		else
			printf "(${notifid}) "
			test_done

			#Start listening for notifications
			${LBNOTIFY} receive -i 10 ${notifid} > $$_notifications.txt &
			recpid=$!
			disown $recpid

			printf "Logging events resulting in DONE state\n"
			$LB_DONE_SH -j ${jobid} > /dev/null 2> /dev/null

			printf "Receiving notifications "
			notif_wait 10 ${jobid} $$_notifications.txt
			kill $recpid >/dev/null 2>&1

			$SYS_GREP ${jobid} $$_notifications.txt > /dev/null

			if [ $? = 0 ]; then
				printf "Notifications were delivered"
				test_done
			else
				printf "Notifications were NOT delivered"
				test_failed
			fi

			$SYS_RM $$_notifications.txt

			#Regress #86772
			printf "Trying to drop invalid NotiID (Regression into bug #86772)..."
			${LBNOTIFY} drop ${jobid} 2>&1 | ${SYS_GREP} "Invalid" > /dev/null
			if [ $? = 0 ]; then
				printf " EINVAL"
				test_done
			else
				printf " no error reported!"
				test_failed
			fi

			#Drop notification
			printf "Dropping the test notification (${notifid})"
			dropresult=`${LBNOTIFY} drop ${notifid} 2>&1`
			if [ -z $dropresult ]; then
				test_done
			else
				test_failed
				print_error "Failed to drop notification ${dropresult}"
			fi

			#Purge test job
			joblist=$$_jobs_to_purge.txt
			echo $jobid > ${joblist}
			try_purge ${joblist}

		fi
	fi
fi

test_end
} 
#} &> $logfile

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK

