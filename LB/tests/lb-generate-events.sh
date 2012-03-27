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
Script for generating test events at a pre-determined rate.

Prerequisities:
   - LB local logger, interlogger, and server running
   - environment variables set:

     GLITE_LB_SERVER_PORT - if nondefault port (9000) is used
     GLITE_LB_LOGGER_PORT - if nondefault port (9002) is used 	
     GLITE_WMS_QUERY_SERVER
     GLITE_WMS_LOG_DESTINATION

Ops called:

    job registration
    event logging

EndHelpHeader

	echo "Usage: $progname [OPTIONS] [event file prefix]"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -n | --n-per-sec       Number of events to send between each 1-s pause."
	echo " -N | --no-of-jobs      Number of jobs to keep unfinished simultaneously."
	echo ""
}


send_next_event ()
{
	NO=$1
	EDG_WL_SEQUENCE=${seq[$NO]}
	currjobid=${jobid[$NO]}

	case "${state[${NO}]}" in

	0)
		printf "%-25s" "Registering testing job "
		currjobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application 2>&1 | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
		jobid[${NO}]=$currjobid
		EDG_WL_SEQUENCE="UI=000000:NS=0000000000:WM=000000:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000002:LBS=000000"
		let "JOBS++"
		;;
	1)
		printf "%-25s" "logging Accepted"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s NetworkServer -e Accepted --from="UserInterface" --from_host="sending component hostname" --from_instance="sending component instance" --local_jobid="new jobId (Condor Globus ...)"`
		;;
	2)
		printf "%-25s" "logging EnQueued"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s NetworkServer -e EnQueued --queue="destination queue" --job="job description in receiver language" --result=OK --reason="detailed description of transfer"`
		;;
	3)
		printf "%-25s" "logging DeQueued"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e DeQueued --queue="queue name" --local_jobid="new jobId assigned by the receiving component"`
		;;
	4)
		printf "%-25s" "logging HelperCall"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e HelperCall --helper_name="name of the called component" --helper_params="parameters of the call" --src_role=CALLING`
		;;
	5)
		printf "%-25s" "logging Match"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e Match --dest_id="${DESTINATION:-destination CE/queue}"`
		;;
	6)
		printf "%-25s" "logging HelperReturn"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e HelperReturn --helper_name="name of the called component" --retval="returned data" --src_role=CALLING`
		;;
	7)
		printf "%-25s" "logging EnQueued"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s WorkloadManager -e EnQueued --queue="destination queue" --job="job description in receiver language" --result=OK --reason="detailed description of transfer"`
		;;
	8)
		printf "%-25s" "logging DeQueued"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s JobController -e DeQueued --queue="queue name" --local_jobid="new jobId assigned by the receiving component"`
		;;
	9)
		printf "%-25s" "logging Transfer"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s JobController -e Transfer --destination="LRMS" --dest_host="destination hostname" --dest_instance="destination instance" --job="job description in receiver language" --result=OK --reason="detailed description of transfer" --dest_jobid="destination internal jobid"`
		;;
	10)
		printf "%-25s" "logging Accepted"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s LogMonitor -e Accepted --from="JobController" --from_host="sending component hostname" --from_instance="sending component instance" --local_jobid="new jobId (Condor Globus ...)"`
		;;
	11)
		printf "%-25s" "logging Transfer"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s LogMonitor -e Transfer --destination="LRMS" --dest_host="destination hostname" --dest_instance="destination instance" --job="job description in receiver language" --result=OK --reason="detailed description of transfer" --dest_jobid="destination internal jobid"`
		;;
	12)
		printf "%-25s" "logging Running"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s LogMonitor -e Running --node="${CE_NODE:-worker node}"`
		;;
	13)
		printf "%-25s" "logging Done"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s LogMonitor -e Done --status_code=OK --reason="reason for the change" --exit_code=0`
		;;
	14)
		printf "%-25s" "logging Clear"
		EDG_WL_SEQUENCE=`${LBLOGEVENT} -j $currjobid -c $EDG_WL_SEQUENCE -s LogMonitor -e Clear --reason=USER`
		;;
	esac
	seq[$NO]="$EDG_WL_SEQUENCE"
}

MAXnoJOBS=20
PerSec=5
JOBS=0

COMMON=lb-common.sh
if [ ! -r ${COMMON} ]; then
        printf "Common definitions '${COMMON}' missing! Some checks will be skipped."
	unset COMMON
fi
source ${COMMON}


while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		"-n" | "--n-per-sec") shift && PerSec=$1 ;;
		"-N" | "--no-of-jobs") shift && MAXnoJOBS=$1 ;;
	esac
	shift
done

	if [ ! -z "$COMMON" ]; then
	        printf "Testing if all binaries are available"
	        check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK $SYS_CAT
	        if [ $? -gt 0 ]; then
			echo "Required binary not present"
			exit 1
	        fi

		# check credentials
		printf "Testing credentials"
		check_credentials_and_generate_proxy
		if [ $? != 0 ]; then
			echo "No proxy available"
			exit 1
		fi
	fi

	for (( i=0; i<$MAXnoJOBS; i++ ))
	do
		state[$i]=0
	done

	CONT="yes"
	while [ "$CONT" = "yes" ]; do

		for (( j=0; j<$PerSec; j++ ))
		do
			let "curr = ($RANDOM + $RANDOM) % $MAXnoJOBS"

			printf "%4d " "$curr"
			send_next_event $curr
			printf "${jobid[$curr]}\n"

			let "state[${curr}] = ${state[${curr}]} + 1"
			if [ ${state[${curr}]} -gt 14 ]; then
				state[${curr}]=0
			fi
		done
		printf "$JOBS jobs so far...\n"
		sleep 1
	done

test_end


