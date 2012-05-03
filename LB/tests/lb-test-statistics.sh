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
Script for testing statistic functions provided by the L&B Service

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

submitted_to_running () {

		EDG_WL_SEQUENCE="UI=000003:NS=0000000000:WM=000000:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000000:LBS=000000"	
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s NetworkServer -e Accepted --from="UserInterface" --from_host="sending component hostname" --from_instance="sending component instance" --local_jobid="new jobId (Condor Globus ...)"`
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s NetworkServer -e EnQueued --queue="destination queue" --job="job description in receiver language" --result=OK --reason="detailed description of transfer"`
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s WorkloadManager -e DeQueued --queue="queue name" --local_jobid="new jobId assigned by the receiving component"`
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s WorkloadManager -e HelperCall --helper_name="name of the called component" --helper_params="parameters of the call" --src_role=CALLING`
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s WorkloadManager -e Match --dest_id="CE$datestr$$"`
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s WorkloadManager -e HelperReturn --helper_name="name of the called component" --retval="returned data" --src_role=CALLING`
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s WorkloadManager -e EnQueued --queue="destination queue" --job="job description in receiver language" --result=OK --reason="detailed description of transfer"`
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s JobController -e DeQueued --queue="queue name" --local_jobid="new jobId assigned by the receiving component"`
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s JobController -e Transfer --destination="LRMS" --dest_host="destination hostname" --dest_instance="destination instance" --job="job description in receiver language" --result=OK --reason="detailed description of transfer" --dest_jobid="destination internal jobid"`
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s LogMonitor -e Accepted --from="JobController" --from_host="sending component hostname" --from_instance="sending component instance" --local_jobid="new jobId (Condor Globus ...)"`
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s LogMonitor -e Transfer --destination="LRMS" --dest_host="destination hostname" --dest_instance="destination instance" --job="job description in receiver language" --result=OK --reason="detailed description of transfer" --dest_jobid="destination internal jobid"`
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s LogMonitor -e Running --node="${CE_NODE:-worker node}"`
}

running_to_done () {

		EDG_WL_SEQUENCE="UI=000003:NS=0000000004:WM=000010:BH=0000000000:JSS=000004:LM=000006:LRMS=000000:APP=000000:LBS=000000"

		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s LogMonitor -e Done --status_code=OK --reason="reason for the change" --exit_code=0`
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $1 -c $EDG_WL_SEQUENCE -s LogMonitor -e Clear --reason=USER`
}



# read common definitions and functions
COMMON=lb-common.sh
NOOFJOBS=10
SEC_COVERAGE=600
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
		"-n" | "--noofjobs") shift ; NOOFJOBS=$1 ;;
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

# check_binaries
printf "Testing if all binaries are available"
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $LBJOBREG $SYS_AWK $LBJOBSTATUS $SYS_DATE $SYS_EXPR $LB_STATS $LB_FROMTO $SYS_BC
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
		datestr=`$SYS_DATE +%Y%m%d%H%M`

		SEQUENCE=`eval "echo {1..${NOOFJOBS}}"`

		for i in $SEQUENCE
		do
		# Register job:
			jobid[$i]=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | ${SYS_GREP} "new jobid" | ${SYS_AWK} '{ print $3 }'`

			if [ -z ${jobid[$i]}  ]; then
				test_failed
				print_error "Failed to register job"
			fi
		done
		printf "Test jobs registered."
		test_done

		printf "Sleeping for 10 seconds... "

		sleep 10

		printf "Sending events for all test jobs, Submitted => Running " 
		for i in $SEQUENCE
		do
			submitted_to_running ${jobid[$i]}
		done
		test_done

		printf "Sleeping for 10 seconds... "

		sleep 10

		printf "Sending events for all test jobs, Running => Done " 
		for i in $SEQUENCE
		do
			running_to_done ${jobid[$i]}
		done
		test_done

		printf "Sleeping for 10 seconds... "

		sleep 10

#		printf "Sending events for all test jobs, Running => Done" 
#		for i in $SEQUENCE
#		do
#			running_to_done ${jobid[$i]}
#		done
#		test_done

		expected_rate=`echo "scale=7;$NOOFJOBS/$SEC_COVERAGE" | bc`
		printf "Getting job rate (should be around $expected_rate, testing if > 0): "
		#rate=`$LB_STATS -n $SEC_COVERAGE CE$datestr$$ 5 | ${SYS_GREP} "Average" | ${SYS_AWK} '{ print $6 }'`
		rate=`$LB_STATS CE$datestr$$ 5 | ${SYS_GREP} "Average" | ${SYS_AWK} '{ print $6 }'`
		cresult=`$SYS_ECHO "$rate > 0" | $SYS_BC`
		printf "$rate"
		if [ "$cresult" -eq "1" ]; then
			test_done
		else
			test_failed
			print_error "Rate other than expected"
		fi

		printf "Getting average 'Submitted' -> 'Running' transfer time (should be a number > 10): "
		$LB_FROMTO CE$datestr$$ 1 5 > fromto.out.$$
		average=`$SYS_CAT fromto.out.$$ | ${SYS_GREP} "Average duration" | ${SYS_AWK} '{ print $5 }'`
		cresult=`$SYS_ECHO "$average > 10" | $SYS_BC`
		printf "$average"
		if [ "$cresult" -eq "1" ]; then
			test_done
		else
			test_failed
			print_error "Average value other than expected"
		fi

		printf "Getting the dispersion index (should be a number >= 0): "
		dispersion=`$SYS_CAT fromto.out.$$ | ${SYS_GREP} "Dispersion index" | ${SYS_AWK} '{ print $3 }'`
		cresult=`$SYS_ECHO "$dispersion >= 0" | $SYS_BC`
		printf "$dispersion"
		if [ "$cresult" -eq "1" ]; then
			test_done
		else
			test_failed
			print_error "Dispersion index value other than expected"
		fi

		$SYS_RM fromto.out.$$


		printf "Getting average 'Submitted' -> 'Done/OK' transfer time (should be a number > 20): "
		$LB_FROMTO CE$datestr$$ 1 6 0 > fromto.out.$$
		doneaverage=`$SYS_CAT fromto.out.$$ | ${SYS_GREP} "Average duration" | ${SYS_AWK} '{ print $5 }'`
		donecresult=`$SYS_ECHO "$doneaverage > 20" | $SYS_BC`
		printf "$doneaverage"
		if [ "$donecresult" -eq "1" ]; then
			test_done
		else
			test_failed
			print_error "Average value other than expected"
		fi

		printf "Comparing. 'Submitted' -> 'Running' should take longer than 'Submitted' -> 'Done/OK': "

		donecresult=`$SYS_EXPR $doneaverage \> $average`
		if [ "$donecresult" -eq "1" ]; then
			printf "OK"
			test_done
		else
			test_failed
			print_error "Done earlier than Running"
		fi

		printf "Long term (Regression into bug #73716): Getting average 'Submitted' -> 'Running' transfer times (should be numbers >= 0):"
		$LB_FROMTO ALL 1 5 > fromto.out.$$
		averages=( $($SYS_CAT fromto.out.$$ | ${SYS_GREP} "Average duration" | ${SYS_SED} 's/^.*": //' | ${SYS_SED} 's/ s.*$//') )
		$SYS_CAT fromto.out.$$ | ${SYS_GREP} "Average duration" | $SYS_SED 's/":.*$//' | $SYS_SED 's/^.*"//' > fromto.out.ces.$$
		dispersions=( $($SYS_CAT fromto.out.$$ | ${SYS_GREP} "Dispersion index" | ${SYS_AWK} '{ print $3 }') )
		printf "\n"

		let i=0 
		$SYS_CAT fromto.out.ces.$$ | while read ce; do
			printf "$i.\t$ce:\t${averages[$i]}\t${dispersions[$i]}"
			cresult=`$SYS_EXPR ${averages[$i]} \>= 0`
			if [ "$cresult" -ne "1" ]; then
				test_failed
				print_error "Bad average value"
			fi
			# Also check dispersion
			cresult=`$SYS_EXPR ${dispersions[$i]} \>= 0`
			if [ "$cresult" -eq "1" ]; then
				test_done
			else
				test_failed
				print_error "Bad dispersion value"
			fi

			let i++
		done 

		$SYS_RM fromto.out.$$
		$SYS_RM fromto.out.ces.$$

                printf "Long term: Getting average 'Running' rates (should be numbers >= 0):"
		$LB_STATS -n 7200 ALL 5 > rates.out.$$
                rates=( $(${SYS_GREP} "Average" rates.out.$$ | ${SYS_SED} 's/^.*": //' | ${SYS_SED} 's/ jobs.*$//') )
                $SYS_CAT rates.out.$$ | ${SYS_GREP} "Average" | $SYS_SED 's/":.*$//' | $SYS_SED 's/^.*"//' > rates.out.ces.$$
                printf "\n"

                let i=0 
                $SYS_CAT rates.out.ces.$$ | while read ce; do
                        printf "$i.\t$ce:\t${rates[$i]}"
                        cresult=`$SYS_EXPR ${rates[$i]} \>= 0`
                        if [ "$cresult" -eq "1" ]; then
                                test_done
                        else
                                test_failed
                                print_error "Bad dispersion value"
                        fi

                        let i++
                done 

                $SYS_RM rates.out.$$
                $SYS_RM rates.out.ces.$$


		#Purge test job
		joblist=$$_jobs_to_purge.txt
		for i in $SEQUENCE
		do
			echo ${jobid[$i]} >> ${joblist}
		done
		try_purge ${joblist}


test_end
}
#} &> $logfile

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK

