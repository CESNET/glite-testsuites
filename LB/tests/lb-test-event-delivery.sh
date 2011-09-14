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
     GLITE_LB_IL_SOCK - if nondefault socket at /tmp/interlogger.sock is used
     GLITE_LB_LOGGER_PORT - if nondefault port (9002) is used 	

Tests called:

    job registration
    event logging
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

CONT="yes"
while [ "$CONT" = "yes" ]; do
	CONT="no"

	# check_binaries
	printf "Testing if all binaries are available"
	check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $LBJOBREG $SYS_AWK $LB_READY_SH $LB_RUNNING_SH $LB_DONE_SH $SYS_AWK $LBJOBLOG
	if [ $? -gt 0 ]; then
		test_failed
	else
		test_done
	fi

	printf "Testing credentials"
	check_credentials_and_generate_proxy
	if [ $? != 0 ]; then
		test_end
		break
	fi

	# Register job:
	printf "Registering testing job "
	jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application`
	if [ $? != 0 ]; then
		test_failed
		print_error "Failed to register job"
		break
	else
		test_done
	fi
	jobid=`echo "${jobid}" | ${SYS_GREP} "new jobid" | ${SYS_AWK} '{ print $3 }'`
	if [ -z $jobid  ]; then
		print_error "Failed to parse job "
		test_end
		exit 4
	else
		printf "($jobid)"
	fi
	
	# log events:
	printf "Logging events resulting in READY state... "
	$LB_READY_SH -j ${jobid} > /dev/null 2> /dev/null

	printf "Sleeping for 10 seconds...\n"

	sleep 10

	jobstate=`${LBJOBSTATUS} ${jobid} | ${SYS_GREP} "state :" | ${SYS_AWK} '{print $3}'`
	printf "Is the testing job ($jobid) in a correct state? $jobstate"

	if [ "${jobstate}" = "Ready" ]; then
		test_done
	else
		test_failed
		print_error "Job is not in appropriate state"
	fi

#	printf "Logging events resulting in RUNNING state\n"
#	$LB_RUNNING_SH -j ${jobid} > /dev/null 2> /dev/null

	printf "Logging events resulting in DONE state... "
	$LB_DONE_SH -j ${jobid} > /dev/null 2> /dev/null

	printf "Sleeping for 10 seconds...\n"

	sleep 10

	jobstate=`${LBJOBSTATUS} ${jobid} | ${SYS_GREP} "state :" | ${SYS_AWK} '{print $3}'`
	printf "Testing job ($jobid) is in state: $jobstate"

	if [ "${jobstate}" = "Done" ]; then
		test_done
	else
		test_failed
		print_error "Job is not in appropriate state"
	fi

	#Purge test job
	joblist=$$_jobs_to_purge.txt
	echo $jobid > ${joblist}

        printf "Registering collection "
        ${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application -C -n 2 -S > $$_test_coll_registration.txt
	jobid=`$SYS_CAT $$_test_coll_registration.txt | ${SYS_GREP} "new jobid" | ${SYS_AWK} '{ print $3 }'`
	if [ -z $jobid  ]; then
		test_failed
		print_error "Failed to register job"
	else
		test_done
		subjobs=( $(cat $$_test_coll_registration.txt | $SYS_GREP EDG_WL_SUB_JOBID | $SYS_SED 's/EDG_WL_SUB_JOBID.*="//' | $SYS_SED 's/"$//') )
		printf "Collection ID: $jobid\n     Subjob 1: ${subjobs[0]}\n     Subjob 2: ${subjobs[1]}\nChecking if subjob registration worked... "
	
		${LBJOBLOG} ${subjobs[0]} | $SYS_GREP 'DG.EVNT="RegJob"' >> /dev/null
		if [ $? = 0 ]; then
			printf "Registration event recorded"
			test_done
		else
			test_failed
			print_error "Subjob registration did not work (Registration event not recorded)"
		fi
	

		job1jdl=`${LBJOBSTATUS} ${subjobs[1]} | ${SYS_GREP} -E "^jdl :" | ${SYS_AWK} '{print $3}'`
		if [ "${job1jdl}" = "(null)" ]; then
			test_failed
			print_error "Subjob registration did not work (JDL not present: "${job1jdl}")"
		else
			printf "JDL present"
			test_done
		fi

		printf "Logging events for subjobs... "
		$LB_READY_SH -j ${subjobs[0]} > /dev/null 2> /dev/null
		$LB_DONE_SH -j ${subjobs[1]} > /dev/null 2> /dev/null

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
		$LB_CLEARED_SH -j ${subjobs[0]} > /dev/null 2> /dev/null
		$LB_CLEARED_SH -j ${subjobs[1]} > /dev/null 2> /dev/null

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

		echo $jobid > $$_jobs_to_purge_test.txt

		printf "Purging collection... " 

		$LBPURGE -j $$_jobs_to_purge_test.txt

		printf "Sleeping for 10 seconds... " 

		sleep 10

		printf "Checking state of collection... " 

		${LBJOBSTATUS} $jobid > $$_collstate.tmp 2> $$_collstate_err.tmp
		jobstate=`$SYS_CAT $$_collstate.tmp | ${SYS_GREP} -E "^state :" | ${SYS_AWK} '{print $3}' 2> $$_collstate.tmp`
		$SYS_GREP "Identifier removed" $$_collstate_err.tmp > /dev/null
		if [ "$?" = "0" -o "${jobstate}" = "Purged" ]; then

			if [ "${jobstate}" = "Purged" ]; then
				printf "${jobstate}"
			else
			printf "Identifier removed"
			fi
			test_done

			printf "Checking state of subjob #1... "
			${LBJOBSTATUS} ${subjobs[0]} > $$_collstate.tmp 2> $$_collstate_err.tmp
			jobstate=`$SYS_CAT $$_collstate.tmp | ${SYS_GREP} -E "^state :" | ${SYS_AWK} '{print $3}' 2> $$_collstate.tmp`
			$SYS_GREP "Identifier removed" $$_collstate_err.tmp > /dev/null
			if [ "$?" = "0" -o "${jobstate}" = "Purged" ]; then
				if [ "${jobstate}" = "Purged" ]; then
					printf "${jobstate}"
				else
					printf "Identifier removed"
				fi
				test_done
			else
				test_failed
				print_error "State ${jobstate}: Job is not in appropriate state (Cleared)"
			fi

			printf "Checking state of subjob #2... "
			${LBJOBSTATUS} ${subjobs[1]} > $$_collstate.tmp 2> $$_collstate_err.tmp
			jobstate=`$SYS_CAT $$_collstate.tmp | ${SYS_GREP} -E "^state :" | ${SYS_AWK} '{print $3}' 2> $$_collstate.tmp`
			$SYS_GREP "Identifier removed" $$_collstate_err.tmp > /dev/null
			if [ "$?" = "0" -o "${jobstate}" = "Purged" ]; then
				if [ "${jobstate}" = "Purged" ]; then
					printf "${jobstate}"
				else
					printf "Identifier removed"
				fi
				test_done
			else
				test_failed
				print_error "State ${jobstate}: Job is not in appropriate state (Cleared)"
			fi

		else
			printf "${jobstate}"
			test_skipped
		fi

		$SYS_RM $$_jobs_to_purge_test.txt
		$SYS_RM $$_collstate.tmp
		$SYS_RM $$_collstate_err.tmp

	fi

	echo ${subjobs[0]} >> ${joblist}
	echo ${subjobs[1]} >> ${joblist}
	echo $jobid >> ${joblist}
	try_purge ${joblist}

	$SYS_RM $$_test_coll_registration.txt


done

test_end
#} &> $logfile
}

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK

