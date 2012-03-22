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
Script for testing interlogger recovery

Prerequisities:
   - LB server, interlogger either running or startable
   - environment variables set:

     GLITE_LB_SERVER_PORT - if nondefault port (9000) is used
     GLITE_LB_IL_SOCK - if nondefault socket at /tmp/interlogger.sock is used
     GLITE_LB_LOGGER_PORT - if nondefault port (9002) is used 	

Tests called:

    job registration
    event logging - through interlogger
    checking jobs states

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
	echo " --stop                 Command to stop the interlogger."
	echo " --start                Command to start the interlogger."
	echo " -f | --file-prefix     IL file prefix."
	echo " -u | --user-name       Name of user account used to run the IL. (default GLITE_USER or 'glite')"
}

function generate_done_events()
{
#outfile = $1 
#user = $2
#host = $3
#jobid = $4

    echo DG.LLLID=28000000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"NetworkServer\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"Accepted\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000001:WM=000000:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000000:LBS=000000\" DG.ACCEPTED.FROM=\"UserInterface\" DG.ACCEPTED.FROM_HOST=\"sending component hostname\" DG.ACCEPTED.FROM_INSTANCE=\"sending component instance\" DG.ACCEPTED.LOCAL_JOBID=\"new jobId \(Condor  Globus ...\)\"  >> $1
    echo DG.LLLID=28003000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"NetworkServer\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"EnQueued\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000003:WM=000000:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000000:LBS=000000\" DG.ENQUEUED.QUEUE=\"destination queue\" DG.ENQUEUED.JOB=\"job description in receiver language\" DG.ENQUEUED.RESULT=\"OK\" DG.ENQUEUED.REASON=\"detailed description of transfer\"  >> $1
    echo DG.LLLID=28006000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"WorkloadManager\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"DeQueued\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000004:WM=000001:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000000:LBS=000000\" DG.DEQUEUED.QUEUE=\"queue name\" DG.DEQUEUED.LOCAL_JOBID=\"new jobId assigned by the receiving component\"  >> $1
    echo DG.LLLID=28009000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"WorkloadManager\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"HelperCall\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000004:WM=000003:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000000:LBS=000000\" DG.HELPERCALL.HELPER_NAME=\"name of the called component\" DG.HELPERCALL.HELPER_PARAMS=\"parameters of the call\" DG.HELPERCALL.SRC_ROLE=\"CALLING\"  >> $1
    echo DG.LLLID=28012000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"WorkloadManager\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"Match\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000004:WM=000005:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000000:LBS=000000\" DG.MATCH.DEST_ID=\"destination CE/queue\"  >> $1
    echo DG.LLLID=28015000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"WorkloadManager\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"HelperReturn\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000004:WM=000007:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000000:LBS=000000\" DG.HELPERRETURN.HELPER_NAME=\"name of the called component\" DG.HELPERRETURN.RETVAL=\"returned data\" DG.HELPERRETURN.SRC_ROLE=\"CALLING\"  >> $1
    echo DG.LLLID=28018000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"WorkloadManager\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"EnQueued\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000004:WM=000009:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000000:LBS=000000\" DG.ENQUEUED.QUEUE=\"destination queue\" DG.ENQUEUED.JOB=\"job description in receiver language\" DG.ENQUEUED.RESULT=\"OK\" DG.ENQUEUED.REASON=\"detailed description of transfer\"  >> $1
    echo DG.LLLID=28021000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"JobController\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"DeQueued\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000004:WM=000010:BH=0000000000:JSS=000001:LM=000000:LRMS=000000:APP=000000:LBS=000000\" DG.DEQUEUED.QUEUE=\"queue name\" DG.DEQUEUED.LOCAL_JOBID=\"new jobId assigned by the receiving component\"  >> $1
    echo DG.LLLID=28024000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"JobController\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"Transfer\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000004:WM=000010:BH=0000000000:JSS=000003:LM=000000:LRMS=000000:APP=000000:LBS=000000\" DG.TRANSFER.DESTINATION=\"LRMS\" DG.TRANSFER.DEST_HOST=\"destination hostname\" DG.TRANSFER.DEST_INSTANCE=\"destination instance\" DG.TRANSFER.JOB=\"job description in receiver language\" DG.TRANSFER.RESULT=\"OK\" DG.TRANSFER.REASON=\"detailed description of transfer\" DG.TRANSFER.DEST_JOBID=\"destination internal jobid\"  >> $1
    echo DG.LLLID=28027000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"LogMonitor\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"Accepted\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000004:WM=000010:BH=0000000000:JSS=000004:LM=000001:LRMS=000000:APP=000000:LBS=000000\" DG.ACCEPTED.FROM=\"JobController\" DG.ACCEPTED.FROM_HOST=\"sending component hostname\" DG.ACCEPTED.FROM_INSTANCE=\"sending component instance\" DG.ACCEPTED.LOCAL_JOBID=\"new jobId \(Condor  Globus ...\)\"  >> $1
    echo DG.LLLID=28030000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"LogMonitor\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"Transfer\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000004:WM=000010:BH=0000000000:JSS=000004:LM=000003:LRMS=000000:APP=000000:LBS=000000\" DG.TRANSFER.DESTINATION=\"LRMS\" DG.TRANSFER.DEST_HOST=\"destination hostname\" DG.TRANSFER.DEST_INSTANCE=\"destination instance\" DG.TRANSFER.JOB=\"job description in receiver language\" DG.TRANSFER.RESULT=\"OK\" DG.TRANSFER.REASON=\"detailed description of transfer\" DG.TRANSFER.DEST_JOBID=\"destination internal jobid\"  >> $1
    echo DG.LLLID=28033000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"LogMonitor\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"Running\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000004:WM=000010:BH=0000000000:JSS=000004:LM=000005:LRMS=000000:APP=000000:LBS=000000\" DG.RUNNING.NODE=\"worker node\"  >> $1
    echo DG.LLLID=28036000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"LogMonitor\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"Done\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000004:WM=000010:BH=0000000000:JSS=000004:LM=000007:LRMS=000000:APP=000000:LBS=000000\" DG.DONE.STATUS_CODE=\"OK\" DG.DONE.REASON=\"reason for the change\" DG.DONE.EXIT_CODE=\"0\"  >> $1
    echo DG.LLLID=28039000 DG.USER=\"$2\" DATE=\"$($SYS_DATE --universal +'%Y%m%d%H%M%S.%N' | sed 's/...$//')\" HOST=\"$3\" PROG=edg-wms LVL=SYSTEM DG.PRIORITY=4 DG.SOURCE=\"LogMonitor\" DG.SRC_INSTANCE=\"\" DG.EVNT=\"Clear\" DG.JOBID=\"$4\" DG.SEQCODE=\"UI=000003:NS=0000000004:WM=000010:BH=0000000000:JSS=000004:LM=000009:LRMS=000000:APP=000000:LBS=000000\" DG.CLEAR.REASON=\"USER\" >> $1
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
if [ -z "$GLITE_USER" ]; then
	USER="glite"
else
	USER="$GLITE_USER"
fi
while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		"-o" | "--output") shift ; logfile=$1 flag=1 ;;
		"-t" | "--text")  setOutputASCII ;;
		"-c" | "--color") setOutputColor ;;
		"-x" | "--html")  setOutputHTML ;;
		"--stop") shift ; STOPCOMMAND="$1" ;;
		"--start") shift ; STARTCOMMAND="$1" ;;
		"-f" | "--file-prefix") shift ; EVENTFILE=$1 ;;
		"-u" | "--user-name") shift ; USER=$1 ;;
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
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $LBJOBREG $SYS_AWK $SYS_DOMAINNAME $LBJOBSTATUS $SYS_FIND $SYS_WC $SYS_EXPR
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
		USERIDENTITY=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^identity" | ${SYS_SED} "s/identity\s*:\s//"`

		# Register job:
		printf "Registering testing job "
		jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | ${SYS_GREP} "new jobid" | ${SYS_AWK} '{ print $3 }'`

		if [ -z $jobid  ]; then
			test_failed
			print_error "Failed to register job"
		else
			printf "($jobid)"
			test_done

			printf "Getting No. of sockets (user $USER) for a later test... "
			SOCKS_PRE=`$SYS_FIND /tmp -maxdepth 1 -type s -user $USER | wc -l`
			printf "$SOCKS_PRE"
			test_done

			#Stopping interlogger (if required)
	                if [ -z $STOPCOMMAND ]; then
				$SYS_ECHO Info: No command to stop was given
			else
				$SYS_ECHO Stoping the interlogger using the stop command supplied
				$STOPCOMMAND
			fi

			UNIQUE=`$SYS_ECHO ${jobid} | ${SYS_SED} 's/.*\///'`

	                if [ -z $EVENTFILE ]; then
        	                #Set the default event file prefix if none has been supplied
                	        EVENTFILE=/var/glite/log/dglogd.log
	                fi

			DOMAINNAME=`${SYS_DOMAINNAME} -f`

			# log events:
			printf "Generating events resulting in CLEARED state\n"

			#Make sure the il is able to access the file, whatever account it is running under. 
			$SYS_TOUCH $EVENTFILE.$UNIQUE
			$SYS_CHMOD 666 $EVENTFILE.$UNIQUE

			generate_done_events "$EVENTFILE.$UNIQUE" "$USERIDENTITY" "$DOMAINNAME" $jobid

			#Starting interlogger or waiting
	                if [ -z "$STARTCOMMAND" ]; then
				$SYS_ECHO Info: No command to start was given
				printf "Sleeping for 70 seconds (waiting for interlogger to notice and deliver events)...\n"
				sleep 70
			else
				$SYS_ECHO Starting the interlogger using the start command supplied
				$STARTCOMMAND > /dev/null 2> /dev/null &
				printf "Sleeping for 10 seconds (waiting for events to deliver)...\n"
				sleep 10
			fi



			jobstate=`${LBJOBSTATUS} ${jobid} | ${SYS_GREP} "state :" | ${SYS_AWK} '{print $3}'`
			printf "Testing job ($jobid) is in state: $jobstate\n"

			if [ "${jobstate}" = "Cleared" ]; then
				test_done
			else
				test_failed
				print_error "Job is not in appropriate state"
			fi


			printf "Getting No. of sockets (regression into Savannah Bug #92708)... "
			SOCKS_POST=`find /tmp -maxdepth 1 -type s -user $USER | wc -l`
			printf "$SOCKS_POST"
			test_done

			check_srv_version '>=' "2.3"
                        if [ $? = 0 ]; then
				printf "Comparing No. of sockets... "
				$SYS_EXPR $SOCKS_POST \> $SOCKS_PRE > /dev/null
				if [ $? -gt 0 ]; then
					printf "OK, less or equal"
					test_done
				else
					test_failed
					print_error "There are more sockets after IL handled messages"
				fi
			else
				printf "Comparing No. of sockets... "
				test_skipped
			fi

			#Purge test job
			joblist=$$_jobs_to_purge.txt
			echo $jobid > ${joblist}
			try_purge ${joblist}

		fi

test_end
}
#} &> $logfile

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK

