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
     GLITE_LB_IL_SOCK - if nondevailt socket at /tmp/interlogger.sock is used
     GLITE_LB_LOGGER_PORT - if nondefault port (9002) is used 	

Tests called:

    job registration
    event logging
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
check_binaries
if [ $? -gt 0 ]; then
	test_failed
else
	test_done
fi

# Register job:
printf "Registering testing job "
jobid=`${LBJOBREG} -m ${EDG_WL_QUERY_SERVER} -s application | grep "new jobid" | awk '{ print $3 }'`

if [ -z $jobid  ]; then
	test_failed
	print_error "Failed to register job"
else
	test_done
	printf "\nRegistered job: $jobid\n"
fi

# log events:
printf "Logging events resulting in READY state\n"
glite-lb-ready.sh -j ${jobid} > /dev/null 2> /dev/null

printf "Sleeping for 10 seconds (waiting for events to deliver)...\n"

sleep 10

jobstate=`${LBJOBSTATUS} ${jobid} | grep "state :" | awk '{print $3}'`
printf "Is the testing job ($jobid) in a correct state? $jobstate"

if [ "${jobstate}" = "Ready" ]; then
        test_done
else
        test_failed
        print_error "Job is not in appropriate state"
fi

printf "Logging events resulting in RUNNING state\n"
glite-lb-running.sh -j ${jobid} > /dev/null 2> /dev/null

printf "Logging events resulting in DONE state\n"
glite-lb-done.sh -j ${jobid} > /dev/null 2> /dev/null

printf "Sleeping for 10 seconds (waiting for events to deliver)...\n"

sleep 10

jobstate=`${LBJOBSTATUS} ${jobid} | grep "state :" | awk '{print $3}'`
printf "Testing job ($jobid) is in state: $jobstate\n"

if [ "${jobstate}" = "Done" ]; then
        test_done
else
        test_failed
        print_error "Job is not in appropriate state"
fi

test_end
} &> $logfile

if [ $flag -ne 1 ]; then
 	cat $logfile
 	rm $logfile
fi
exit $TEST_OK

