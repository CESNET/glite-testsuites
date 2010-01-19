#!/bin/bash

# show help and usage
progname=`basename $0`
showHelp()
{
cat << EndHelpHeader
Script for testing correct event delivery

Prerequisities:
   - LB delivery chain - logger, interlogger, server
   - environment variables set:

     GLITE_LB_SERVER_PORT - if nondefault port (9000) is used
     GLITE_WMS_LBPROXY_STORE_SOCK - if nondefault socket /tmp/lb_proxy_store.sock

Tests called:

    job registration
    proxy-based event logging
    checking events 

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

# check_binaries
printf "Testing if all binaries are available"
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $LBJOBREG $SYS_AWK $LB_READY_SH $LB_RUNNING_SH $LB_DONE_SH $SYS_AWK 
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
		jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | ${SYS_GREP} "new jobid" | ${SYS_AWK} '{ print $3 }'`

		if [ -z $jobid  ]; then
			test_failed
			print_error "Failed to register job"
		else
			test_done
			printf "\nRegistered job: $jobid\n"
		fi

		# log events:
		printf "Logging events resulting in READY state\n"
		$LB_READY_SH -X ${GLITE_WMS_LBPROXY_STORE_SOCK}store.sock -j ${jobid} > /dev/null 2> /dev/null

		printf "Sleeping for 10 seconds (waiting for events to deliver)...\n"

		jobstate=`${LBJOBSTATUS} ${jobid} | ${SYS_GREP} "state :" | ${SYS_AWK} '{print $3}'`
		printf "Is the testing job ($jobid) in a correct state? $jobstate"

		if [ "${jobstate}" = "Ready" ]; then
			test_done
		else
			test_failed
			print_error "Job is not in appropriate state"
		fi

		printf "Logging events resulting in RUNNING state\n"
		$LB_RUNNING_SH -X ${GLITE_WMS_LBPROXY_STORE_SOCK}store.sock -j ${jobid} > /dev/null 2> /dev/null

		printf "Logging events resulting in DONE state\n"
		$LB_DONE_SH -X ${GLITE_WMS_LBPROXY_STORE_SOCK}store.sock -j ${jobid} > /dev/null 2> /dev/null

		printf "Sleeping for 10 seconds (waiting for events to deliver)...\n"

		jobstate=`${LBJOBSTATUS} ${jobid} | ${SYS_GREP} "state :" | ${SYS_AWK} '{print $3}'`
		printf "Testing job ($jobid) is in state: $jobstate\n"

		if [ "${jobstate}" = "Done" ]; then
			test_done
		else
			test_failed
			print_error "Job is not in appropriate state"
		fi

		#Purge test job
		joblist=$$_jobs_to_purge.txt
		echo $jobid > ${joblist}
		try_purge ${joblist}

	fi
fi

test_end
} &> $logfile

if [ $flag -ne 1 ]; then
 	cat $logfile
 	rm $logfile
fi
exit $TEST_OK
