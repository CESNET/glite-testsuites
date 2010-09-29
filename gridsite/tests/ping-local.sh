#!/bin/bash
# $Id$

# show help and usage
progname=`basename $0`
showHelp()
{
cat << EndHelpHeader
Script for testing the GridSite components locally

Prerequisities:
   - Apache with the GridSite module enabled running on local machine

Tests:
   - Checks that Apache is running and listening to port 443.
   - Checks that the GridSite module is loaded in the Apache configuration

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
check_binaries $SYS_LSOF $SYS_GREP $SYS_SED $SYS_PS $SYS_PIDOF
if [ $? -gt 0 ]; then
	test_failed
else
	test_done
fi

# Apache running:
printf "Testing if Apache is running"
if [ "$(${SYS_PIDOF} ${SYS_APACHE})" ]; then
	test_done
else
	test_failed
	print_error "Apache server is not running"
fi

# GridSite module loaded:
printf "Testing if GridSite is loaded"
${SYS_APACHECTL} -t -D DUMP_MODULES 2>&1| grep mod_gridsite >/dev/null 2>&1
if [ $? -eq 0 ]; then
	test done
else
	test_failed
	print_error "GridSite is not loaded in Apache"
fi

# Server listening:
printf "Testing if Apache is listening on port 443"
check_listener ${SYS_APACHE} 443
if [ $? -eq 0 ]; then
        test_done
else
        test_failed
        print_error "Apache server is not listening on port 443"
fi

test_end
} &> $logfile

if [ $flag -ne 1 ]; then
 	cat $logfile
 	$SYS_RM $logfile
fi
exit $TEST_OK

