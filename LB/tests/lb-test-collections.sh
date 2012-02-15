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
Script for testing collection-specific features

Prerequisities:
   - LB local logger, interlogger, and server running
   - environment variables set:

     GLITE_LB_SERVER_PORT - if nondefault port (9000) is used
     GLITE_LB_LOGGER_PORT - if nondefault port (9002) is used   
     GLITE_WMS_QUERY_SERVER

Tests called:

    collection registration
    status queries

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
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK $LBJOBREG $LBQUERYEXT
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

		# Register job:
		printf "Registering testing collection "
		jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application -C -n 5 | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`

		if [ -z $jobid  ]; then test_failed
			print_error "Failed to register job"
		else
			printf "($jobid)"
			test_done

			printf "Request children with only the parent ID (Regression into bug #47774)... "
			echo parent_job=$jobid > query.$$.ext

			$LBQUERYEXT -i query.$$.ext > query.$$.res 2> query.$$.err

			CHILDREN=`wc -l query.$$.res | $SYS_AWK ' { print $1 }'`

			if [ $CHILDREN -eq 5 ]; then
				printf "$CHILDREN returned"
				test_done
			else
				$SYS_GREP -i "No indexed condition" query.$$.err
				if [ $? -eq 0 ]; then
					test_failed
					print_error "built-in index on parent job not used, query refused."
				else
					test_failed
					print_error "built-in index on parent job not used, query refused, error message NULL!"
				fi
			fi

			$SYS_RM query.$$.ext query.$$.res query.$$.err

			#Purge test job
			joblist=$$_jobs_to_purge.txt
			echo $jobid > ${joblist}
			try_purge ${joblist}
			$SYS_RM ${joblist}
		fi

test_end
}
exit $TEST_OK

