#!/bin/bash
# $Header$
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

# read common definitions and functions
COMMON=`dirname $0`/lb-common.sh
if [ ! -r ${COMMON} ]; then
	printf "Common definitions '${COMMON}' missing!\n"
	exit 2
fi
source ${COMMON}

# show help and usage
progname=`basename $0`
showHelp()
{
cat << EndHelpHeader
Script for checking that the LB binaries are installed.

Prerequisities:
   - LB client packages installed, on $PATH or under $GLITE_LOCATION/bin

Tests called:

    check_binaries

Returned values:
    Exit TEST_OK: Test Passed
    Exit TEST_ERROR: Test Failed
    Exit 2: Wrong Input

EndHelpHeader

	echo "Usage: $progname [OPTIONS]"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -t | --text            Format output as plain ASCII text."
	echo " -c | --color           Format output as text with ANSI colours (autodetected by default)."
	echo " -x | --html            Format output as html."
}

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

##
#  Starting the test
#####################

test_start

# check_binaries
printf "Testing if all binaries are available"
# With no arguments, which is a pass rather than an error - a list of what to
# check was never filled in here (the TODO copied with the function says as much),
# so this proves only that the library is sourced and the report works. Each test
# checks the binaries it actually runs; docs/lb.md repeats what this one does not.
check_binaries
if [ $? -gt 0 ]; then
	test_failed
	print_error "Some binaries are missing"
	exit $TEST_ERROR
else
	test_done
fi

test_end

exit $TEST_OK

