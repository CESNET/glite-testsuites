#!/bin/bash
# $Header$

# read common definitions and functions
COMMON=lb-common.sh
if [ ! -r ${COMMON} ]; then
	printf "Common definitions '${COMMON}' missing!"
	exit 2
fi
source ${COMMON}

##
#  Starting the test
#####################

test_start

# check_binaries
printf "Testing if all binaries are available"
check_binaries
if [ $? -gt 0 ]; then
	test_failed
	print_error "Some binaries are missing"
	exit $TEST_ERR
else
	test_done
fi

test_end

exit $TEST_OK

