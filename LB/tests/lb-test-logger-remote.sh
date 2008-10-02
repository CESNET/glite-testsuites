#!/bin/bash
# $Header$

# show help and usage
progname=`basename $0`
showHelp()
{
cat << EndHelpHeader
Script for testing remotely the LB logger

Prerequisities:
   - LB logger running on remote machine
   - environment variables set:

     GLITE_LB_LOGGER_PORT - if nondefault port (9002) is used

Tests called:
    check_binaries() - check if all necessary binaries are locally available
    ping_host() - network ping to LB server host
    check_socket() - simple tcp echo to the LB logger port

Returned values:
    Exit TEST_OK: Test Passed
    Exit TEST_ERROR: Test Failed
    Exit 2: Wrong Input

EndHelpHeader

	echo "Usage: $progname [OPTIONS] host"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -o | --output 'file'   Redirect all output to the 'file' (stdout by default)."
	echo " -t | --text            Format output as plain ASCII text."
	echo " -c | --color           Format output as text with ANSI colours (autodetected by default)."
	echo " -x | --html            Format output as html."
	echo ""
	echo "where host is the LB logger host, it must be specified everytime."
}
if [ -z "$1" ]; then
	showHelp
	exit 2
fi

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
		*) LB_HOST=$1 ;;
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

######################
# Starting the test  #
######################

{
test_start

# check_binaries
printf "Testing if all binaries are available"
check_binaries $TEST_SOCKET $SYS_PING $SYS_GREP
if [ $? -gt 0 ]; then
        test_failed
	print_error "Some binaries are missing"
else
        test_done
fi

# ping_host:
printf "Testing ping to LB logger ${LB_HOST}"
ping_host ${LB_HOST}
if [ $? -gt 0 ]; then
	test_failed
	print_error "Destination host might be unreachable"
else
	test_done
fi

# check_services
printf "Testing LB logger at ${LB_HOST}:${GLITE_LB_LOGGER_PORT} (logging)"
check_socket ${LB_HOST} ${GLITE_LB_LOGGER_PORT}
if [ $? -gt 0 ]; then
	test_failed
	print_error "LB logger at ${LB_HOST}:${GLITE_LB_LOGGER_PORT} might be unreachable"
else
	test_done
fi

test_end
} &> $logfile

if [ $flag -ne 1 ]; then
 	cat $logfile
 	rm $logfile
fi
exit $TEST_OK

