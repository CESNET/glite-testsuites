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

	echo "Usage: $progname [OPTIONS] [event file prefix]"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -o | --output 'file'   Redirect all output to the 'file' (stdout by default)."
	echo " -t | --text            Format output as plain ASCII text."
	echo " -c | --color           Format output as text with ANSI colours (autodetected by default)."
	echo " -x | --html            Format output as html."
	echo ""
	echo "Give the same prefix you pass to your local logger on startup (-f or --file-prefix option)"
	echo "If no event file prefix is given, the default will be used (/var/glite/log/dglogd.log)."
}


generate_reference_file()
{
        echo "line 1: edg_wll_ParseEvent() o.k. (event Accepted), edg_wll_UnparseEvent() o.k." > $1
        echo "line 2: edg_wll_ParseEvent() o.k. (event EnQueued), edg_wll_UnparseEvent() o.k." >> $1
        echo "line 3: edg_wll_ParseEvent() o.k. (event DeQueued), edg_wll_UnparseEvent() o.k." >> $1
        echo "line 4: edg_wll_ParseEvent() o.k. (event HelperCall), edg_wll_UnparseEvent() o.k." >> $1
        echo "line 5: edg_wll_ParseEvent() o.k. (event Match), edg_wll_UnparseEvent() o.k." >> $1
        echo "line 6: edg_wll_ParseEvent() o.k. (event HelperReturn), edg_wll_UnparseEvent() o.k." >> $1
        echo "line 7: edg_wll_ParseEvent() o.k. (event EnQueued), edg_wll_UnparseEvent() o.k." >> $1
        echo "line 8: edg_wll_ParseEvent() o.k. (event DeQueued), edg_wll_UnparseEvent() o.k." >> $1
        echo "line 9: edg_wll_ParseEvent() o.k. (event Transfer), edg_wll_UnparseEvent() o.k." >> $1
        echo "line 10: edg_wll_ParseEvent() o.k. (event Accepted), edg_wll_UnparseEvent() o.k." >> $1
        echo "line 11: edg_wll_ParseEvent() o.k. (event Transfer), edg_wll_UnparseEvent() o.k." >> $1
        echo "line 12: edg_wll_ParseEvent() o.k. (event Running), edg_wll_UnparseEvent() o.k." >> $1
        echo "line 13: edg_wll_ParseEvent() o.k. (event Done), edg_wll_UnparseEvent() o.k." >> $1
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
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $LBJOBREG $SYS_AWK $LBPARSEEFILE 
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

		UNIQUE=`$SYS_ECHO ${jobid} | ${SYS_SED} 's/.*\///'`

		if [ -z $EVENTFILE ]; then
			#Set the default event file prefix if none has been supplied
			EVENTFILE=/var/glite/log/dglogd.log
		fi

		printf "Testing if event file exists ($EVENTFILE.$UNIQUE) "
		if [ -f $EVENTFILE.$UNIQUE ]; then
			test_done

			#Test the contents of the file

			#process events file
			$LBPARSEEFILE -f $EVENTFILE.$UNIQUE 2>&1 | $SYS_GREP -v "Parsing file" > events.tested.$$.txt 

			generate_reference_file events.reference.$$.txt

			printf "Comparing results (<) with expectations (>) ... "
			diff events.tested.$$.txt events.reference.$$.txt
			if [ $? = 0 ]; then
				printf "(MATCH)"
				test_done
			else
				printf "Comparison failed, details above"
				test_failed
			fi

			echo Cleaning up
			$SYS_RM events.tested.$$.txt
			$SYS_RM events.reference.$$.txt
		else
			test_failed
			echo ""
			echo "* Test file not found. Possible reasons:"
			echo "*   - Local logger is not running and the file was never created."
			echo "*   - You have not specified a correct event file prefix."
			echo "*     Note that you need to give the same prefix used to start"
			echo "*     the local logger daemon."
			#echo "*   - Interlogger is running and has already processed and removed"
			#echo "*     the file. Stop the interlogger for this test."
			echo ""
		fi

		#Purge test job
		joblist=$$_jobs_to_purge.txt
		echo $jobid > ${joblist}
		try_purge ${joblist}


test_end
} &> $logfile

if [ $flag -ne 1 ]; then
 	cat $logfile
 	$SYS_RM $logfile
fi
exit $TEST_OK

