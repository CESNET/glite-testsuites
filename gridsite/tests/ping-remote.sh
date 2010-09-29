#!/bin/bash
# $Id$

# show help and usage
progname=`basename $0`
showHelp()
{
cat << EndHelpHeader
Script for testing The GridSite components remotely

Prerequisities:
   - Apache with the GridSite module enabled running on remote machine

Tests:
   - ping_host() - network ping to Apache server host
   - check_socket() - simple tcp echo to port 443 of the host

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
	echo "where host is the Apache server host, it must be specified everytime."
}
if [ -z "$1" ]; then
	showHelp
	exit 2
fi

# read common definitions and functions
COMMON=gridsite-common.sh
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
		*) APACHE_HOST=$1 ;;
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
check_binaries $SYS_NC $SYS_PING $SYS_GREP
if [ $? -gt 0 ]; then
	test_failed
	print_error "Some binaries are missing"
else
	test_done
fi

# ping_host:
printf "Testing ping to Apache server ${APACHE_HOST}"
ping_host ${APACHE_HOST}
if [ $? -gt 0 ]; then
	test_failed
	print_error "Destination host might be unreachable"
else
	test_done
fi
 
# check_services
printf "Testing Apache server at ${APACHE_HOST}:443"
check_socket ${APACHE_HOST} 443
if [ $? -gt 0 ]; then
	test_failed
	print_error "Apache server at ${APACHE_HOST}:443 might be unreachable"
else
	test_done
fi

test_end
} &> $logfile

if [ $flag -ne 1 ]; then
 	cat $logfile
 	$SYS_RM $logfile
fi
exit $TEST_OK

