#!/bin/bash

# show help and usage
progname=`basename $0`
showHelp()
{
cat << EndHelpHeader
Script for testing the LB server locally

Prerequisities:
   - LB server running on local machine
   - environment variables set:

     GLITE_LB_SERVER_PORT - if nondefault port (9000) is used

Tests called:

    pidof - return instance PIDs of the given binary
    mysqladmin ping - check for response by the mysql server
    check_socket() - simple tcp echo to all LB server ports
      (by default 9000 for logging, 9001 for querying, 9003 for web services)

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

# mySQL running:
printf "Testing if mySQL is running"
if [ "$(${SYS_PIDOF} ${SYS_MYSQLD})" ]; then
	test_done
else
	test_failed
	print_error "mySQL server is not running"
fi

# mySQL accessible:
printf "Testing if mySQL is accessible"
if [ "$(${SYS_MYSQLADMIN} ${SYS_PING})" ]; then
	test_done
else
	test_failed
	print_error "mySQL server is not answering"
fi

# server running:
printf "Testing if LB Server is running"
if [ "$(${SYS_PIDOF} ${LB_SERVER})" ]; then
	test_done
else
	test_failed
	print_error "${LB_SERVER} server is not running"
fi

# Server listening:
printf "Testing if LB Server is listening on port ${GLITE_LB_SERVER_PORT}"
check_listener ${LB_SERVER} ${GLITE_LB_SERVER_PORT}
if [ $? -gt 0 ]; then
        test_failed
        print_error "LB server is not listening on port ${GLITE_LB_SERVER_PORT}"
else
        test_done
fi

# Server listening:
printf "Testing if LB Server is listening on port ${GLITE_LB_SERVER_QPORT}"
check_listener ${LB_SERVER} ${GLITE_LB_SERVER_QPORT}
if [ $? -gt 0 ]; then
        test_failed
        print_error "LB server is not listening on port ${GLITE_LB_SERVER_QPORT}"
else
        test_done
fi

# Server listening:
printf "Testing if LB Server is listening on port ${GLITE_LB_SERVER_WPORT}"
check_listener ${LB_SERVER} ${GLITE_LB_SERVER_WPORT}
if [ $? -gt 0 ]; then
        test_failed
        print_error "LB server is not listening on port ${GLITE_LB_SERVER_WPORT}"
else
        test_done
fi


# Interlogger running:
printf "Testing if Interlogger is running"
if [ "$(pidof ${LB_INTERLOGD})" ]; then
	test_done
else
	test_failed
	print_error "${LB_INTERLOGD} server is not running"
fi


# Interlogger listening on socket:
printf "Testing if interlogger is listening on socket ${GLITE_LB_IL_SOCK}" 
check_socket_listener ${LB_INTERLOGD} ${GLITE_LB_IL_SOCK}
if [ $? -gt 0 ]; then
        test_failed
        print_error "LB interlogger is not listening on socket ${GLITE_LB_IL_SOCK}"
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

