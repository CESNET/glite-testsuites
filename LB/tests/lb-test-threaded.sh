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
Script for tebasic sting of threaded client

Prerequisities:
   - LB server
   - environment variables set:

     GLITE_LB_SERVER_PORT - if nondefault port (9000) is used

Tests called:

    job registration

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
#touch $logfile
#if [ ! -w $logfile ]; then
#	echo "Cannot write to output file $logfile"
#	exit $TEST_ERROR
#fi

DEBUG=2

##
#  Starting the test
#####################

{
test_start


# check_binaries
printf "Testing if all binaries are available"
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK

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
		# Register jobs:

		reg_error="0"
		printf "Registering testing jobs "
		for i in {0..30}
		do
			printf " $i"
			jobid[$i]=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`

			if [ -z ${jobid[$i]}  ]; then
				test_failed
				print_error "Failed to register a job"
				reg_error="1"
			fi
		done
		if [ "$reg_error" = "0" ]; then
			test_done

			# Check results
			printf "Asking for states of all 30 jobs..."
			for i in {0..30}
			do
				jobids="$jobids ${jobid[$i]}"
			done


			#echo $LBTHRJOBSTATUS $jobids
			$LBTHRJOBSTATUS $jobids > threads.$$.tmp 2>/dev/null
			test_done

			printf "Checking if states were returned for all jobs..."
			let grep_error=0
			for i in {0..30}
			do
				printf " $i"
				$SYS_GREP ${jobid[$i]} threads.$$.tmp > /dev/null 2> /dev/null
				if [ $? != 0 ]; then
					printf "(!)"
					let grep_error++
				fi
			done

			if [ "$grep_error" = "0" ]; then
				test_done
			else
				test_failed
				print_error "Status not retrieved for $grep_error jobs"
			fi

			rm threads.$$.tmp

			#Purge test jobs
#			joblist=$$_jobs_to_purge.txt
#			for i in {0..30}
#			do
#				echo ${jobid[$i]} >> ${joblist}
#			done
#			try_purge ${joblist}

		fi
		

test_end
}
#} &> $logfile

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK

