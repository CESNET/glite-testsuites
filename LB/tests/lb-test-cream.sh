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
Script for testing if jobs pass through correct states through their lifetimes

Prerequisities:
   - LB local logger, interlogger, and server running
   - environment variables set:

     GLITE_LB_SERVER_PORT - if nondefault port (9000) is used
     GLITE_LB_LOGGER_PORT - if nondefault port (9002) is used 	
     GLITE_WMS_QUERY_SERVER
     GLITE_WMS_LOG_DESTINATION

Tests called:

    job registration
    event logging

Returned values:
    Exit TEST_OK: Test Passed
    Exit TEST_ERROR: Test Failed
    Exit 2: Wrong Input

EndHelpHeader

	echo "Usage: $progname [OPTIONS] [event file prefix]"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -o | --output 'file'   Redirect all output to the 'file' (stdout by default)."
	echo " -t | --text            Format output as plain ASCII text."
	echo " -c | --color           Format output as text with ANSI colours (autodetected by default)."
	echo " -x | --html            Format output as html."
	echo ""
}

test_state () {

        wmsstate=`${LBJOBSTATUS} $1 | ${SYS_GREP} -w "state :" | ${SYS_AWK} '{ print $3 }'`
	creamstate=`${LBJOBSTATUS} $1 | ${SYS_GREP} -w "cream_state :" | ${SYS_AWK} '{ print $3 }'`
        #printf "Testing job ($1) is in state: $wmsstate (should be $2) and $creamstate (should be $3)"
        printf "Testing job is in state: $wmsstate $creamstate (should be $2 $3)"

        if [ "${wmsstate}" = "$2" -a "${creamstate}" = "$3" ]; then
                test_done
        else
                test_failed
                print_error "Job is not in appropriate state"
        fi

}

check_return_and_test_state ()
{
# 1: previous return value
# 2: jobid
# 3: expected wms state
# 4: expected cream state
#	printf "Sleeping for 10 seconds (waiting for events to deliver)...\n"
	if [ $1 = 0 ]; then
		test_done
	else
		test_failed
	fi

        sleep 2

	test_state $2 $3 $4
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
		*) EVENTFILE=$1 ;;
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
	check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $LBJOBREG $SYS_AWK $LBJOBSTATUS
	if [ $? -gt 0 ]; then
		test_failed
		print_error "Some binaries are missing"
		break
	else
		test_done
	fi
	
	# check credentials
	printf "Testing credentials"
	check_credentials_and_generate_proxy
	if [ $? != 0 ]; then
		break
	fi

	printf "Testing job sumbitted directly to CREAM-CE\n"
	
	# Register job:
	printf "Registering testing job "
	local_jobid="CREAM-test-"`date +%s`
	jobid="https://"$GLITE_WMS_QUERY_SERVER/"$local_jobid"
	${LBJOBREG} -j $jobid -m ${GLITE_WMS_QUERY_SERVER} -s CREAMExecutor -c > /dev/null
	if [ $? != 0 ]; then
		test_failed
		print_error "Failed to register job"
		break
	else
		test_done
	fi

	printf "Jobid: ($jobid)\n"

	test_state $jobid Submitted Registered

	EDG_WL_SEQUENCE="UI=000003:NS=0000000000:WM=000000:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000000:LBS=000000"	

	printf "logging Accepted"
	EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMAccepted --from="CREAMExecutor" --from_host="sending component hostname" --from_instance="sending component instance" --local_jobid=$local_jobid`
	check_return_and_test_state $? $jobid Submitted Registered

	printf "logging CREAMStatus Pending"
	EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Registered --new_state=Pending --result=Arrived`
	EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Registered --new_state=Pending --result=Done`
	check_return_and_test_state $? $jobid Waiting Pending

	printf "logging CREAMStatus Idle"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Pending --new_state=Idle --result=Arrived`
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Pending --new_state=Idle --result=Done`
        check_return_and_test_state $? $jobid Scheduled Idle

	printf "logging CREAMStatus Running"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Idle --new_state=Running --result=Arrived`
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Idle --new_state=Running --result=Done`
        check_return_and_test_state $? $jobid Running Running

	printf "logging CREAMStatus Really-running"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Running --new_state=Really-running --result=Arrived`
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Running --new_state=Really-running --result=Done`
        check_return_and_test_state $? $jobid Running Really-running

	printf "logging CREAMStatus Done-ok"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Really-running --new_state=Done-ok --result=Arrived`
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Really-running --new_state=Done-ok --result=Done`
        check_return_and_test_state $? $jobid Done Done-ok

	#Purge test job
        joblist=$$_jobs_to_purge.txt
        echo $jobid > ${joblist}
        try_purge ${joblist}

	printf "\nTesting job submitted to CREAM-CE via WMS\n"

	jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application`
        if [ $? != 0 ]; then
                test_failed
                print_error "Failed to register job"
                break
        else
                test_done
        fi

	#parse job id
        jobid=`echo "${jobid}" | ${SYS_GREP} "new jobid" | ${SYS_AWK} '{ print $3 }'`
        if [ -z $jobid  ]; then
                print_error "Failed to parse job "
                break
        else
                printf "($jobid)\n"
        fi

        test_state $jobid Submitted

	EDG_WL_SEQUENCE="UI=000003:NS=0000000000:WM=000000:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000000:LBS=000000"

	printf "logging Accepted"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s NetworkServer -e Accepted --from="UserInterface" --from_host="sending component hostname" --from_instance="sending component instance" --local_jobid="new jobId (Condor Globus ...)"`
#        check_return_and_test_state $? $jobid Waiting 

	printf "\nlogging DeQueued"
	EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e DeQueued --queue="queue name" --local_jobid="new jobId assigned by the receiving component"`
#	check_return_and_test_state $? $jobid Waiting

	printf "\nlogging HelperCall"
	EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e HelperCall --helper_name="name of the called component" --helper_params="parameters of the call" --src_role=CALLING`
#	check_return_and_test_state $? $jobid Waiting
#
	printf "\nlogging Match"
	EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e Match --dest_id="${DESTINATION:-destination CE/queue}"`
#	check_return_and_test_state $? $jobid Waiting
#
	printf "\nlogging HelperReturn"
	EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e HelperReturn --helper_name="name of the called component" --retval="returned data" --src_role=CALLING`
	check_return_and_test_state $? $jobid Waiting

	printf "logging CREAMAccepted"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMAccepted --from="CREAMExecutor" --from_host="sending component hostname" --from_instance="sending component instance" --local_jobid="CREAM_FAKE_JOBID"`
        check_return_and_test_state $? $jobid Waiting

	printf "logging CREAMStore CmdStart"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMInterface -e CREAMStore --command=CmdStart --result=Start`
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMInterface -e CREAMStore --command=CmdStart --result=Ok`
        check_return_and_test_state $? $jobid Waiting Pending

        printf "logging CREAMStatus Pending"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Registered --new_state=Pending --result=Arrived`
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Registered --new_state=Pending --result=Done`
        check_return_and_test_state $? $jobid Waiting Pending

	printf "logging EnQueued"
	EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e EnQueued --queue="destination queue" --job="job description in receiver language" --result=OK --reason="detailed description of transfer"`
#	check_return_and_test_state $? $jobid Ready Pending

	printf "\nlogging DeQueued"
	EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s JobController -e DeQueued --queue="queue name" --local_jobid="new jobId assigned by the receiving component"`
#	check_return_and_test_state $? $jobid Ready Pending

#	printf "logging CREAMAccepted"
#        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMAccepted --from="CREAMExecutor" --from_host="sending component hostname" --from_instance="sending component instance" --local_jobid="CREAM_FAKE_JOBID"`
#       check_return_and_test_state $? $jobid Ready Registered

	printf "\nlogging Transfer"
	EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s JobController -e Transfer --destination="LRMS" --dest_host="destination hostname" --dest_instance="destination instance" --job="job description in receiver language" --result=OK --reason="detailed description of transfer" --dest_jobid="destination internal jobid"`
	check_return_and_test_state $? $jobid Ready Pending

#	printf "logging CREAMStore CmdStart"
#        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMInterface -e CREAMStore --command=CmdStart --result=Start`
#        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMInterface -e CREAMStore --command=CmdStart --result=Ok`
#        check_return_and_test_state $? $jobid Ready Pending	

#	printf "logging CREAMStatus Pending"
#        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Registered --new_state=Pending --result=Arrived`
#        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Registered --new_state=Pending --result=Done`
#        check_return_and_test_state $? $jobid Ready Pending

        printf "logging CREAMStatus Idle"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Pending --new_state=Idle --result=Arrived`
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Pending --new_state=Idle --result=Done`
        check_return_and_test_state $? $jobid Scheduled Idle

        printf "logging CREAMStatus Running"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Idle --new_state=Running --result=Arrived`
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Idle --new_state=Running --result=Done`
        check_return_and_test_state $? $jobid Running Running

	printf "logging CREAMStore CmdSuspend (bug #45971)"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMInterface -e CREAMStore --command=CmdSuspend --result=Start`
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMInterface -e CREAMStore --command=CmdSuspend --result=Ok`
        check_return_and_test_state $? $jobid Running Running

	printf "testing if job is suspended (bug #45971)"
	susp=`${LBJOBSTATUS} $jobid | ${SYS_GREP} "suspended :" | ${SYS_AWK} '{ print $3 }'`
	if [ $susp = "1" ]; then
		test_done
	else
		test_failed
	fi

	printf "logging CREAMStatus Idle (bug #45971)"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Running --new_state=Idle --result=Arrived`
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Running --new_state=Idle --result=Done`
        check_return_and_test_state $? $jobid Scheduled Idle

	printf "testing if job is suspended (bug #45971)"
        susp=`${LBJOBSTATUS} $jobid | ${SYS_GREP} "suspended :" | ${SYS_AWK} '{ print $3 }'`
        if [ $susp = "0" ]; then
               test_done
        else
               test_failed
        fi

	printf "logging CREAMStatus Running (bug #45971)"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Idle --new_state=Running --result=Arrived`
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Idle --new_state=Running --result=Done`
        check_return_and_test_state $? $jobid Running Running

	printf "testing if job is suspended (bug #45971)"
        susp=`${LBJOBSTATUS} $jobid | ${SYS_GREP} "suspended :" | ${SYS_AWK} '{ print $3 }'`
        if [ $susp = "0" ]; then
                test_done
        else
                test_failed
        fi

	printf "logging CREAMStatus Really-running"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Running --new_state=Really-running --result=Arrived`
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Running --new_state=Really-running --result=Done`
        check_return_and_test_state $? $jobid Running Really-running

	printf "logging CREAMStatus Done-ok"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Really-running --new_state=Done-ok --result=Arrived`
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Really-running --new_state=Done-ok --result=Done`
        check_return_and_test_state $? $jobid Done Done-ok

	printf "logging Done"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s LogMonitor -e Done --status_code=OK --reason="reason for the change" --exit_code=0`
        check_return_and_test_state $? $jobid Done Done-ok

	printf "logging Clear"
        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s LogMonitor -e Clear --reason=USER`
        check_return_and_test_state $? $jobid Cleared Done-ok	

	#Purge test job
	joblist=$$_jobs_to_purge.txt
	echo $jobid > ${joblist}
	try_purge ${joblist}
done

test_end
}
#} &> $logfile

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK

