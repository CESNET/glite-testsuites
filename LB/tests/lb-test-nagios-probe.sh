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
Script for testing correct job registration

Prerequisities:
   - LB server
   - environment variables set:

     GLITE_WMS_QUERY_SERVER

Tests called:

    L&B's nagios probe

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


printf "Checking if the probe is available..."

PROBE="$GLITE_LOCATION/libexec/grid-monitoring/probes/emi.lb/LB-probe"

if [ -f "$PROBE" ]; then
	test_done

	# check_binaries
	printf "Testing if all binaries are available"
	check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK $SYS_CAT
	if [ $? -gt 0 ]; then
		test_failed
	else
		test_done
	fi

	printf "Testing credentials"
	check_credentials_and_generate_proxy
	if [ $? != 0 ]; then
		test_end
		exit 2
	fi

	printf "Running the nagios probe..."
	PROBEOUTPUT=`${PROBE} -H $GLITE_WMS_QUERY_SERVER 2> /dev/null`
	PROBECODE=$?

	printf " \"$PROBEOUTPUT\", ret. code $PROBECODE"
	$SYS_ECHO $PROBEOUTPUT | $SYS_GREP -E "^OK" > /dev/null 2> /dev/null
	if [ $? -eq 0 -a $PROBECODE -eq 0 ]; then
		test_done
	else
		if [ "$PROBEOUTPUT" != "" -a $PROBECODE -ne 0 ]; then
			test_warning
		else
			test_failed
		fi
	fi

else
	printf " Probe not available"
	test_skipped
fi

test_end
}

exit $TEST_OK

