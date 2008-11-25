#!/bin/bash

# show help and usage
progname=`basename $0`
showHelp()
{
cat << EndHelpHeader
Script for testing if local logger is accepting events

Prerequisities:
   - LB local logger, server
   - environment variables set:

     GLITE_LB_SERVER_PORT - if nondefault port (9000) is used
     GLITE_LB_LOGGER_PORT - if nondefault port (9002) is used 	

Tests called:

    job registration
    event logging

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
		jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | ${SYS_GREP} "new jobid" | ${SYS_AWK} '{ print $3 }'`

		if [ -z $jobid  ]; then
			test_failed
			print_error "Failed to register job"
		else
			printf "($jobid)"
			test_done
		fi

		printf "Logging events\n"

		EDG_WL_SEQUENCE="UI=000003:NS=0000000000:WM=000000:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000000:LBS=000000"	

		printf "logging Accepted"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s NetworkServer -e Accepted --from="UserInterface" --from_host="sending component hostname" --from_instance="sending component instance" --local_jobid="new jobId (Condor Globus ...)"`
		if [ $? = 0 ]; then
			test_done
		else
			test_failed
		fi

		printf "logging EnQueued"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s NetworkServer -e EnQueued --queue="destination queue" --job="job description in receiver language" --result=OK --reason="detailed description of transfer"`
		if [ $? = 0 ]; then
			test_done
		else
			test_failed
		fi

		printf "logging DeQueued"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e DeQueued --queue="queue name" --local_jobid="new jobId assigned by the receiving component"`
		if [ $? = 0 ]; then
			test_done
		else
			test_failed
		fi

		printf "logging HelperCall"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e HelperCall --helper_name="name of the called component" --helper_params="parameters of the call" --src_role=CALLING`
		if [ $? = 0 ]; then
			test_done
		else
			test_failed
		fi

		printf "logging Match"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e Match --dest_id="${DESTINATION:-destination CE/queue}"`
		if [ $? = 0 ]; then
			test_done
		else
			test_failed
		fi

		printf "logging HelperReturn"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e HelperReturn --helper_name="name of the called component" --retval="returned data" --src_role=CALLING`
		if [ $? = 0 ]; then
			test_done
		else
			test_failed
		fi

		printf "logging EnQueued"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e EnQueued --queue="destination queue" --job="job description in receiver language" --result=OK --reason="detailed description of transfer"`
		if [ $? = 0 ]; then
			test_done
		else
			test_failed
		fi

		printf "logging DeQueued"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s JobController -e DeQueued --queue="queue name" --local_jobid="new jobId assigned by the receiving component"`
		if [ $? = 0 ]; then
			test_done
		else
			test_failed
		fi

		printf "logging Transfer"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s JobController -e Transfer --destination="LRMS" --dest_host="destination hostname" --dest_instance="destination instance" --job="job description in receiver language" --result=OK --reason="detailed description of transfer" --dest_jobid="destination internal jobid"`
		if [ $? = 0 ]; then
			test_done
		else
			test_failed
		fi

		printf "logging Accepted"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s LogMonitor -e Accepted --from="JobController" --from_host="sending component hostname" --from_instance="sending component instance" --local_jobid="new jobId (Condor Globus ...)"`
		if [ $? = 0 ]; then
			test_done
		else
			test_failed
		fi

		printf "logging Transfer"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s LogMonitor -e Transfer --destination="LRMS" --dest_host="destination hostname" --dest_instance="destination instance" --job="job description in receiver language" --result=OK --reason="detailed description of transfer" --dest_jobid="destination internal jobid"`
		if [ $? = 0 ]; then
			test_done
		else
			test_failed
		fi

		printf "logging Running"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s LogMonitor -e Running --node="${CE_NODE:-worker node}"`
		if [ $? = 0 ]; then
			test_done
		else
			test_failed
		fi

		printf "logging Done"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $jobid -c $EDG_WL_SEQUENCE -s LogMonitor -e Done --status_code=OK --reason="reason for the change" --exit_code=0`
		if [ $? = 0 ]; then
			test_done
		else
			test_failed
		fi


		#Purge test job
		joblist=$$_jobs_to_purge.txt
		echo $jobid > ${joblist}
		try_purge ${joblist}

	fi
fi

test_end
} &> $logfile

if [ $flag -ne 1 ]; then
 	cat $logfile
 	rm $logfile
fi
exit $TEST_OK

