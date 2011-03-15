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
Script for testing correct event delivery

Prerequisities:
   - LB delivery chain - logger, interlogger, server
   - environment variables set:

     GLITE_LB_SERVER_PORT - if nondefault port (9000) is used
     GLITE_WMS_LBPROXY_STORE_SOCK - if nondefault socket /tmp/lb_proxy_store.sock

Tests called:

    job registration
    proxy-based event logging
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
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $LBJOBREG $SYS_AWK $LB_READY_SH $LB_RUNNING_SH $LB_DONE_SH $SYS_AWK 
if [ $? -gt 0 ]; then
	test_failed
else
	test_done
fi

printf "Testing credentials"

timeleft=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^timeleft" | ${SYS_SED} "s/timeleft\s*:\s//"`

if [ "$timeleft" = "" ]; then
	test_failed
	print_error "No credentials"
else
	if [ "$timeleft" = "0:00:00" ]; then
		test_failed
		print_error "Credentials expired"
	else
		test_done


		# Register job:
		printf "Registering testing job "
		jobid=`${LBJOBREG} -X ${GLITE_WMS_LBPROXY_STORE_SOCK}store.sock -m ${GLITE_WMS_QUERY_SERVER} -s application | ${SYS_GREP} "new jobid" | ${SYS_AWK} '{ print $3 }'`

		if [ -z $jobid  ]; then
			test_failed
			print_error "Failed to register job"
		else
			test_done
			printf "\nRegistered job: $jobid\n"
		fi

		jobstate=`${LBJOBSTATUS} ${jobid} | ${SYS_GREP} "state :" | ${SYS_AWK} '{print $3}'`
		printf "Is the testing job ($jobid) in a correct state? $jobstate"

		if [ "${jobstate}" = "Submitted" ]; then
			test_done
		else
			test_failed
			print_error "State ${jobstate}: Job is not in appropriate state (Submitted)"
		fi

		# log events:
		printf "Logging events resulting in READY state... "
		$LB_READY_SH -X ${GLITE_WMS_LBPROXY_STORE_SOCK}store.sock -j ${jobid} > /dev/null 2> /dev/null

		printf "Sleeping for 10 seconds... \n"
		sleep 10

		jobstate=`${LBJOBSTATUS} ${jobid} | ${SYS_GREP} "state :" | ${SYS_AWK} '{print $3}'`
		printf "Is the testing job ($jobid) in a correct state? $jobstate" 
		if [ "${jobstate}" = "Ready" ]; then
			test_done
		else
			test_failed
			print_error "State ${jobstate}: Job is not in appropriate state (Ready)"
		fi

		printf "Logging events for the testing job... "
		$LB_RUNNING_SH -X ${GLITE_WMS_LBPROXY_STORE_SOCK}store.sock -j ${jobid} > /dev/null 2> /dev/null
		$LB_DONE_SH -X ${GLITE_WMS_LBPROXY_STORE_SOCK}store.sock -j ${jobid} > /dev/null 2> /dev/null

		printf "Sleeping for 10 seconds...\n"
		sleep 10

		jobstate=`${LBJOBSTATUS} ${jobid} | ${SYS_GREP} "state :" | ${SYS_AWK} '{print $3}'`
		printf "Testing job ($jobid) is in state: $jobstate"

		if [ "${jobstate}" = "Done" ]; then
			test_done
		else
			test_failed
			print_error "State ${jobstate}: Job is not in appropriate state (Done)"
		fi

		#Purge test job
		joblist=$$_jobs_to_purge.txt
		echo $jobid > ${joblist}

		printf "Registering collection "
		${LBJOBREG} -X ${GLITE_WMS_LBPROXY_STORE_SOCK}store.sock -m ${GLITE_WMS_QUERY_SERVER} -s application -C -n 2 -S > $$_test_coll_registration.txt
		jobid=`$SYS_CAT $$_test_coll_registration.txt | ${SYS_GREP} "new jobid" | ${SYS_AWK} '{ print $3 }'`
		if [ -z $jobid  ]; then
			test_failed
			print_error "Failed to register job"
		else
			test_done
			subjobs=( $(cat $$_test_coll_registration.txt | $SYS_GREP EDG_WL_SUB_JOBID | $SYS_SED 's/EDG_WL_SUB_JOBID.*="//' | $SYS_SED 's/"$//') )
			printf "Collection ID: $jobid\n     Subjob 1: ${subjobs[0]}\n     Subjob 2: ${subjobs[1]}\nChecking if subjob registration worked... "

			job1jdl=`${LBJOBSTATUS} ${subjobs[0]} | ${SYS_GREP} -E "^jdl :" | ${SYS_AWK} '{print $3}'`
			if [ "${job1jdl}" = "(null)" ]; then
				test_failed
				print_error "Subjob registration did not work (JDL not present: "${job1jdl}")"
			else
				printf "JDL present"
				test_done
			fi

			printf "Checking if subjob has stateEnterTime set... "
			j1stateenter=`${LBJOBSTATUS} ${subjobs[0]} | $SYS_GREP "stateEnterTime :" | $SYS_SED 's/stateEnterTime :\s*//' `
			cresult=`$SYS_EXPR $j1stateenter= \> 0`
			if [ "$cresult" -eq "1" ]; then
				printf "$j1stateenter (`$SYS_DATE -d @$j1stateenter`)"
				test_done
			else
				test_failed
				print_error "stateEnterTime not set"
			fi

			

			printf "Logging events for subjobs... "
			$LB_READY_SH -X ${GLITE_WMS_LBPROXY_STORE_SOCK}store.sock -j ${subjobs[0]} > /dev/null 2> /dev/null
			$LB_DONE_SH -X ${GLITE_WMS_LBPROXY_STORE_SOCK}store.sock -j ${subjobs[1]} > /dev/null 2> /dev/null
			
			printf "Sleeping for 10 seconds (waiting for events to deliver)...\n"
			sleep 10

			jobstate=`${LBJOBSTATUS} ${subjobs[0]} | ${SYS_GREP} "state :" | ${SYS_AWK} '{print $3}'`
			printf "Is the testing job (${subjobs[0]}) in a correct state? $jobstate"
	
			if [ "${jobstate}" = "Ready" ]; then
				test_done
			else
				test_failed
				print_error "State ${jobstate}: Job is not in appropriate state (Ready)"
			fi

			jobstate=`${LBJOBSTATUS} ${subjobs[1]} | ${SYS_GREP} "state :" | ${SYS_AWK} '{print $3}'`
			printf "Is the testing job (${subjobs[1]}) in a correct state? $jobstate"
	
			if [ "${jobstate}" = "Done" ]; then
				test_done
			else
				test_failed
				print_error "State ${jobstate}: Job is not in appropriate state (Done)"
			fi


			jobstate=`${LBJOBSTATUS} -fullhist $jobid | ${SYS_GREP} -E "^state :" | ${SYS_AWK} '{print $3}'`
			printf "Is the collection ($jobid) in a correct state? $jobstate"
	
			if [ "${jobstate}" = "Waiting" ]; then
				test_done
			else
				test_failed
				print_error "State ${jobstate}: Job is not in appropriate state (Waiting)"
			fi

			printf "Logging events to clear subjobs... "
			$LB_CLEARED_SH -X ${GLITE_WMS_LBPROXY_STORE_SOCK}store.sock -j ${subjobs[0]} > /dev/null 2> /dev/null
			$LB_CLEARED_SH -X ${GLITE_WMS_LBPROXY_STORE_SOCK}store.sock -j ${subjobs[1]} > /dev/null 2> /dev/null

			printf "Sleeping for 10 seconds (waiting for events to deliver)...\n"
			sleep 10

			jobstate=`${LBJOBSTATUS} -fullhist $jobid | ${SYS_GREP} -E "^state :" | ${SYS_AWK} '{print $3}'`
			printf "Is the collection ($jobid) in a correct state? $jobstate"

			if [ "${jobstate}" = "Cleared" ]; then
				test_done
			else
				test_failed
				print_error "State ${jobstate}: Job is not in appropriate state (Cleared)"
			fi
		fi




		echo ${subjobs[0]} >> ${joblist}
		echo ${subjobs[1]} >> ${joblist}
		echo $jobid >> ${joblist}
		try_purge ${joblist}

		$SYS_RM $$_test_coll_registration.txt

	fi
fi

test_end
}
#} &> $logfile

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK

