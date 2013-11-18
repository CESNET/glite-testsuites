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
Script for testing L&B dump and load actions

Prerequisities:
   - LB server
   - environment variables set:

     GLITE_LB_SERVER_PORT - if nondefault port (9000) is used
     GLITE_LB_LOGGER_PORT - if nondefault port (9002) is used
     GLITE_WMS_QUERY_SERVER

Tests called:

    job registration
    collection registration
    event delivery
    server dump
    server purge
    dump file load

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
	echo " -R | --reps <R>        Perform R repetitions for each job type. (Default 9)"
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
REPS=9
while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		"-o" | "--output") shift ; logfile=$1 flag=1 ;;
		"-t" | "--text")  setOutputASCII ;;
		"-c" | "--color") setOutputColor ;;
		"-x" | "--html")  setOutputHTML ;;
		"-R" | "--reps") shift; REPS=$1 ;;
	esac
	shift
done

RET=$TEST_OK

DEBUG=2

##
#  Starting the test
#####################

get_state()
{
	$SSL_CMD ${1}?text
	$SYS_CAT https.$$.tmp | $SYS_GREP -E "^Status=" | $SYS_SED 's/^.*=//'
	$SYS_RM https.$$.tmp
}

{
test_start

while true; do

	# check_binaries
	printf "Testing if all binaries are available"
	check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK $LBJOBREG $LBJOBSTATUS $LBPURGE
	if [ $? -gt 0 ]; then
		test_failed
		RET=2
		break 
	else
		test_done
	fi

	printf "Testing credentials"
	check_credentials_and_generate_proxy
	if [ $? != 0 ]; then
		test_end
		RET=2
		break
	fi

	check_srv_version '>=' "2.3"
        if [ $? -ne 0 ]; then
		printf "No point checking."
		test_skipped
		break
	fi
	test_done

	X509_USER_PROXY=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^path" | ${SYS_SED} "s/path\s*:\s//"`

	printf "Using SSL client: "
	$SYS_CURL --version | head -n 1 | grep -i NSS/ >/dev/null 2>&1
	if [ $? -eq 0 ]; then
	        SSL_CMD="wget --timeout=60 --no-check-certificate --secure-protocol=SSLv3 --quiet --private-key $X509_USER_PROXY --certificate $X509_USER_PROXY --ca-directory /etc/grid-security/certificates --ca-certificate $X509_USER_PROXY --output-document https.$$.tmp"
	        SSL_CLIENT=wget
	else
	        SSL_CMD="$SYS_CURL --max-time 60 --insecure -3 --silent --key $X509_USER_PROXY --cert $X509_USER_PROXY --capath /etc/grid-security/certificates --output https.$$.tmp"
	        SSL_CLIENT=curl
	fi
	printf "$SSL_CLIENT"
	test_done


	printf "Sleep 1 to get a unique second... "
	sleep 1
	test_done
	printf "Get start time ... "
	starttime=`$SYS_DATE --utc +%Y%m%d%H%M%S`
	printf "$starttime"
	test_done
	printf "Sleep 1 to make sure arrival times are all greater... "
	sleep 1
	test_done

	states[10]="Submitted"
	states[11]="Running"
	states[12]="Running"
	states[13]="Submitted"
	states[14]="Running"
	states[15]="Submitted"
	states[16]="Unknown"
	states[17]="Submitted"
	states[18]="Running"
	states[19]="Submitted"
	states[20]="Ready"
	states[21]="Done"
	states[22]="Submitted"
	states[23]="Submitted"
	states[24]="Running"
	states[25]="Submitted"
	states[26]="Running"
	states[27]="Submitted"
	states[28]="Waiting"
	states[29]="Waiting"
	states[30]="Submitted"

	desc[10]="Simple job"
	desc[11]="Simple job"
	desc[12]="Collection"
	desc[13]="Col Subjob"
	desc[14]="Col Subjob"
	desc[15]="Col Subjob"
	desc[16]="Grey job  "
	desc[17]="DAG       "
	desc[18]="DAG Subjob"
	desc[19]="DAG Subjob"
	desc[20]="Simple job"
	desc[21]="Input SB"
	desc[22]="Output SB"
	desc[23]="Simple job"
	desc[24]="Input Coll"
	desc[25]="SBC Subjob"
	desc[26]="SBC Subjob"
	desc[27]="Output SB"
	desc[28]="CREAM job"
	desc[29]="CREAM-WMS"
	desc[30]="Simple ACLs"

	for i in {a..z}; do idchars="$i${idchars}"; done
	for i in {A..Z}; do idchars="$i${idchars}"; done
	for i in {0..9}; do idchars="$i${idchars}"; done
	idchars="${idchars}-_"

	# Register jobs
	for (( y=1; y<=$REPS; y++ )); do
		printf "Registering testing jobs. Simple, registration only... "
		jobid[${y}10]=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
		printf "(${jobid[${y}10]})"
		test_done

		printf "Simple, state running... "
		jobid[${y}11]=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
		$LB_RUNNING_SH -j ${jobid[${y}11]} > /dev/null 2> /dev/null
		printf "(${jobid[${y}11]})"
		test_done

		printf "Collection, various states... "
		${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application -C -n 3 > coll.reg.$$.out
		jobid[${y}12]=`$SYS_CAT coll.reg.$$.out | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
		printf "${jobid[${y}12]}"
		test_done
		for i in {10..12}; do
			let q=i+3
			let w=$i-10
			jobid[${y}${q}]=`$SYS_CAT coll.reg.$$.out | $SYS_GREP "EDG_WL_SUB_JOBID\[$w\]" | $SYS_SED 's/EDG_WL_SUB_JOBID\[[0-9]*\]="//' | $SYS_SED 's/"$//'`
			printf " - ${jobid[${y}$q]}\n"
		done
		$LB_RUNNING_SH -j ${jobid[${y}14]} > /dev/null 2> /dev/null

		$SYS_RM coll.reg.$$.out

		printf "Grey job, running... "
		uniq=""
		for i in {0..21}; do 
			q=$RANDOM%65;
			q=$q+1;
			uniq="$uniq${idchars:${q}:1}";
		done
		SKIP_GREY=0

		jobid[${y}16]=`echo ${jobid[${y}10]} | $SYS_GREP -o -E "https://.*/"`
		jobid[${y}16]="${jobid[${y}16]}$uniq"
		printf "${jobid[${y}16]}"

		glite-lb-logevent -j ${jobid[${y}16]} -c UI=000000:NS=0000000004:WM=000010:BH=0000000000:JSS=000004:LM=000004:LRMS=000000:APP=000002:LBS=000000 -s LogMonitor -e Running --node="worker node" > /dev/null 2> /dev/null
		test_done

		printf "DAG, various states... "
		${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application -S -n 2 > coll.reg.$$.out
		jobid[${y}17]=`$SYS_CAT coll.reg.$$.out | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
		printf "${jobid[${y}17]}"
		test_done
		for i in {10..11}; do
			let q=i+8
			let w=$i-10
			jobid[${y}${q}]=`$SYS_CAT coll.reg.$$.out | $SYS_GREP "EDG_WL_SUB_JOBID\[$w\]" | $SYS_SED 's/EDG_WL_SUB_JOBID\[[0-9]*\]="//' | $SYS_SED 's/"$//'`
			printf " - ${jobid[${y}$q]}\n"
		done
		$LB_RUNNING_SH -j ${jobid[${y}18]} > /dev/null 2> /dev/null

		$SYS_RM coll.reg.$$.out

		printf "Regular job with input and output sandbox... "
                ${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application > sbtestjob.$$.out
                jobid[${y}20]=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
                seqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "EDG_WL_SEQUENCE" | ${SYS_SED} 's/EDG_WL_SEQUENCE=//' | ${SYS_SED} 's/"//g'`
                $SYS_RM sbtestjob.$$.out
		printf "${jobid[${y}20]}"
		test_done

                $LBREGSANDBOX --jobid ${jobid[${y}20]} --input --from http://users.machine/path/to/sandbox.file --to file://where/it/is/sandbox.file --sequence $seqcode > sbtestjob.$$.out
                jobid[${y}21]=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_LB_ISB_JOBID" | ${SYS_SED} 's/GLITE_LB_ISB_JOBID=//' | ${SYS_SED} 's/"//g'`
                isbseqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_LB_ISB_SEQUENCE" | ${SYS_SED} 's/GLITE_LB_ISB_SEQUENCE=//' | ${SYS_SED} 's/"//g'`
                seqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_WMS_SEQUENCE_CODE" | ${SYS_SED} 's/GLITE_WMS_SEQUENCE_CODE=//' | ${SYS_SED} 's/"//g'`
                $SYS_RM sbtestjob.$$.out
		printf " - Input:  ${jobid[${y}21]}"
		test_done

                $LBREGSANDBOX --jobid ${jobid[${y}20]} --output --from file://where/it/is/sandbox.file2 --to http://users.machine/path/to/sandbox.file2 --sequence $seqcode > sbtestjob.$$.out
                jobid[${y}22]=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_LB_OSB_JOBID" | ${SYS_SED} 's/GLITE_LB_OSB_JOBID=//' | ${SYS_SED} 's/"//g'`
                osbseqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_LB_OSB_SEQUENCE" | ${SYS_SED} 's/GLITE_LB_OSB_SEQUENCE=//' | ${SYS_SED} 's/"//g'`
                $SYS_RM sbtestjob.$$.out

                isbseqcode=`$LBLOGEVENT --source LRMS --jobid ${jobid[${y}21]} --sequence $isbseqcode --event FileTransfer --result OK`
		printf " - Output: ${jobid[${y}22]}"
		test_done

		$LB_READY_SH -j ${jobid[${y}20]} > /dev/null 2> /dev/null
		
		printf "Regular job with input and output sandbox collections... "
                ${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application > sbtestjob.$$.out
                jobid[${y}23]=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
                seqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "EDG_WL_SEQUENCE" | ${SYS_SED} 's/EDG_WL_SEQUENCE=//' | ${SYS_SED} 's/"//g'`
                $SYS_RM sbtestjob.$$.out
                printf "${jobid[${y}23]}"
                test_done

                $LBREGSANDBOX --jobid ${jobid[${y}23]} --input --from http://users.machine/path/to/sandbox.file --to file://where/it/is/sandbox.file --sequence $seqcode -n 2 > sbtestjob.$$.out 2> sbtestjob.$$.err
		jobid[${y}24]=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_LB_ISB_JOBID" | ${SYS_SED} 's/GLITE_LB_ISB_JOBID=//' | ${SYS_SED} 's/"//g'`
		isbseqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_LB_ISB_SEQUENCE" | ${SYS_SED} 's/GLITE_LB_ISB_SEQUENCE=//' | ${SYS_SED} 's/"//g'`
		seqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_WMS_SEQUENCE_CODE" | ${SYS_SED} 's/GLITE_WMS_SEQUENCE_CODE=//' | ${SYS_SED} 's/"//g'`
		jobid[${y}25]=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "EDG_WL_SUB_JOBID\[0\]" | ${SYS_SED} 's/EDG_WL_SUB_JOBID\[0\]=//' | ${SYS_SED} 's/"//g'`
		jobid[${y}26]=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "EDG_WL_SUB_JOBID\[1\]" | ${SYS_SED} 's/EDG_WL_SUB_JOBID\[1\]=//' | ${SYS_SED} 's/"//g'`
		isbseqcode=`$LBLOGEVENT --source LRMS --jobid ${jobid[${y}26]} --sequence $isbseqcode --event FileTransfer --result START`
		printf " - Input:  ${jobid[${y}24]}\n   -       ${jobid[${y}25]}\n   -       ${jobid[${y}26]}\n"
		$SYS_RM sbtestjob.$$.out

                $LBREGSANDBOX --jobid ${jobid[${y}23]} --output --from file://where/it/is/sandbox.file2 --to http://users.machine/path/to/sandbox.file2 --sequence $seqcode > sbtestjob.$$.out
                jobid[${y}27]=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_LB_OSB_JOBID" | ${SYS_SED} 's/GLITE_LB_OSB_JOBID=//' | ${SYS_SED} 's/"//g'`
		printf " - Output: ${jobid[${y}27]}\n"
		$SYS_RM sbtestjob.$$.out sbtestjob.$$.err

		printf "CREAM job... "
	        local_jobid="CREAM-test-"`date +%s`
	        jobid[${y}28]="https://"$GLITE_WMS_QUERY_SERVER/"$local_jobid"
	        ${LBJOBREG} -j ${jobid[${y}28]} -m ${GLITE_WMS_QUERY_SERVER} -s CREAMExecutor -c > /dev/null

	        EDG_WL_SEQUENCE="UI=000003:NS=0000000000:WM=000000:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000000:LBS=000000"
	        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j ${jobid[${y}28]} -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMAccepted --from="CREAMExecutor" --from_host="sending component hostname" --from_instance="sending component instance" --local_jobid=$local_jobid`
	        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j ${jobid[${y}28]} -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Registered --new_state=Pending --result=Arrived`
	        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j ${jobid[${y}28]} -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMStatus --old_state=Registered --new_state=Pending --result=Done`
                printf "${jobid[${y}28]}"
		test_done

		printf "CREAM job through WMS... "
	        jobid[${y}29]=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application`
	        jobid[${y}29]=`echo "${jobid[${y}29]}" | ${SYS_GREP} "new jobid" | ${SYS_AWK} '{ print $3 }'`

	        EDG_WL_SEQUENCE="UI=000003:NS=0000000000:WM=000000:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000000:LBS=000000"

	        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j ${jobid[${y}29]} -c $EDG_WL_SEQUENCE -s NetworkServer -e Accepted --from="UserInterface" --from_host="sending component hostname" --from_instance="sending component instance" --local_jobid="new jobId (Condor Globus ...)"`
	        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j ${jobid[${y}29]} -c $EDG_WL_SEQUENCE -s WorkloadManager -e DeQueued --queue="queue name" --local_jobid="new jobId assigned by the receiving component"`
	        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j ${jobid[${y}29]} -c $EDG_WL_SEQUENCE -s WorkloadManager -e HelperCall --helper_name="name of the called component" --helper_params="parameters of the call" --src_role=CALLING`
	        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j ${jobid[${y}29]} -c $EDG_WL_SEQUENCE -s WorkloadManager -e Match --dest_id="${DESTINATION:-destination CE/queue}"`
	        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j ${jobid[${y}29]} -c $EDG_WL_SEQUENCE -s WorkloadManager -e HelperReturn --helper_name="name of the called component" --retval="returned data" --src_role=CALLING`
	        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j ${jobid[${y}29]} -c $EDG_WL_SEQUENCE -s CREAMExecutor -e CREAMAccepted --from="CREAMExecutor" --from_host="sending component hostname" --from_instance="sending component instance" --local_jobid="CREAM_FAKE_JOBID"`
	        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j ${jobid[${y}29]} -c $EDG_WL_SEQUENCE -s CREAMInterface -e CREAMStore --command=CmdStart --result=Start`
	        EDG_WL_SEQUENCE=`${LBLOGEVENT} -j ${jobid[${y}29]} -c $EDG_WL_SEQUENCE -s CREAMInterface -e CREAMStore --command=CmdStart --result=Ok`
                printf "${jobid[${y}29]}"
		test_done

		printf "Simple, with ACLs... "
		jobid[${y}30]=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
		seqcode="UI=000000:NS=0000000000:WM=000000:BH=0000000000:JSS=000000:LM=000000:LRMS=000000:APP=000002:LBS=000000"
		printf "(${jobid[${y}30]})"
		seqcode=`$LBLOGEVENT -e ChangeACL -s UserInterface -p -j "${jobid[${y}30]}" --user_id "RemovedIdentity" --user_id_type DN --permission "READ" --permission_type ALLOW --operation "ADD" -c $seqcode`
		seqcode=`$LBLOGEVENT -e ChangeACL -s UserInterface -p -j "${jobid[${y}30]}" --user_id "TestIdentity" --user_id_type DN --permission "READ" --permission_type ALLOW --operation "ADD" -c $seqcode`
		$LBLOGEVENT -e ChangeACL -s UserInterface -p -j "${jobid[${y}30]}" --user_id "RemovedIdentity" --user_id_type DN --permission "READ" --permission_type ALLOW --operation "REMOVE" -c $seqcode > /dev/null
		test_done

	done

	printf "Allow 10 s for delivery... "
	sleep 10
	test_done

	printf "Checking states...\n"
	for (( y=1; y<=$REPS; y++ )); do
		for i in {10..30}; do
			real=`get_state ${jobid[${y}$i]}`
			if [ "$real" == "${states[$i]}" ]; then
				printf "${jobid[${y}$i]}\t${desc[$i]}\t$real"
				test_done
			else
				if [ $i -eq 16 ]; then #Skip grey
					printf "${jobid[${y}$i]}\t${desc[$i]}\t(Support off)"
					test_skipped
					SKIP_GREY=1
				else
					test_failed
					print_error "${jobid[${y}$i]} (${desc[$i]}) in state $real, should be ${states[$i]}"
				fi
			fi
		done
		aclline=`$LBJOBSTATUS ${jobid[${y}30]} | $SYS_GREP -E "^acl"`
		acltest=`$SYS_ECHO $aclline | $SYS_GREP -o "<auri>.*<\/auri>" | $SYS_SED 's/<[\/]*auri>//g'`
		if [ "$acltest" == "dn:TestIdentity" ]; then
			printf "${jobid[${y}30]} (${desc[$i]}) ACL \"$acltest\""
			test_done
		else
			test_failed
			print_error "Job ${jobid[${y}30]} has improper ACL setting: \"$aclline\""
		fi
	done

	printf "Sleep 1 to get a unique second... "
	sleep 1
	printf "Get end time... "
	endtime=`$SYS_DATE --utc +%Y%m%d%H%M%S`
	printf "$endtime"
	test_done

	printf "Dump test jobs... "
	dumpfile=`$LBDUMP -f $starttime -t $endtime | $SYS_GREP "dumped to the file" | $SYS_SED 's/^.*dumped to the file .//' | $SYS_SED 's/. at the server.//'`
	printf "$dumpfile"
	test_done

	printf "Getting No. of events dumped... "
	dumpev=`$SYS_CAT $dumpfile | $SYS_GREP -v -E "^$" | wc -l`
	printf "$dumpev"
	test_done

#	uu=`echo ${jobid[01]} | sed 's/^.*\///'`
#	mysql --batch -u lbserver lbserverZS -e "select * from events where jobid='$uu'" > ev.pre

	printf "Purging test jobs... "
	joblist=$$_jobs_to_purge.txt
	for (( y=1; y<=$REPS; y++ )); do
		for i in {10..30}; do
			echo ${jobid[${y}$i]} >> ${joblist}
		done
	done
	${LBPURGE} -j ${joblist} > /dev/null
	test_done

	isThereZombie=0
	printf "Checking states...\n"
	for (( y=1; y<=$REPS; y++ )); do
		for i in {10..30}; do
			if [ $i -eq 16 ]; then #Skip grey
				continue
			fi
			$LBJOBSTATUS ${jobid[${y}$i]} 2>&1 | grep "Identifier removed" > /dev/null
			if [ $? -eq 0 ]; then 
				printf "${jobid[${y}$i]}\tEIDRM"
				isThereZombie=1
				test_done
			else
				test_failed
				print_error "${jobid[${y}$i]} not a zombie"
			fi
		done
	done

	if [ $isThereZombie -eq 0 ]; then
		printf "No job was purged. No point continuing... "
		test_skipped
		break
	fi

#	mysql --batch -u lbserver lbserverZS -e "select * from events where jobid='$uu'" > ev.mid

	printf "Load test jobs... "
	$LBLOAD -f $dumpfile
	test_done

#	mysql --batch -u lbserver lbserverZS -e "select * from events where jobid='$uu'" > ev.post

	printf "Checking states...\n"
	for (( y=1; y<=$REPS; y++ )); do
		for i in {10..30}; do
			real=`get_state ${jobid[${y}$i]}`
			if [ "$real" == "${states[$i]}" ]; then
				printf "${jobid[${y}$i]}\t${desc[$i]}\t$real"
				test_done
			else
				if [ $i -eq 16 -a $SKIP_GREY -eq 1 ]; then #Skip grey
					printf "${jobid[${y}$i]}\t${desc[$i]}\t---"
					test_skipped
				else
					test_failed
					print_error "${jobid[${y}$i]} (${desc[$i]}) in state \"$real\", should be \"${states[$i]}\""
				fi
			fi
		done
		if [ "$acltest" == "dn:TestIdentity" ]; then
			printf "${jobid[${y}30]} (${desc[$i]}) ACL \"$acltest\""
			test_done
		else
			test_failed
			print_error "Job ${jobid[${y}30]} has improper ACL setting: \"$aclline\""
		fi
	done

	printf "Purging test jobs... "
	${LBPURGE} -j ${joblist} > /dev/null
	$SYS_RM ${joblist}
	test_done
		
	break
done		

test_end
}

exit $RET

