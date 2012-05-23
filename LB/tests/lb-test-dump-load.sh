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

RET=$TEST_OK

DEBUG=2

##
#  Starting the test
#####################

get_state()
{
	$SSL_CMD ${1}?text
	$SYS_CAT https.$$.tmp | $SYS_GREP -E "^Status=" | $SYS_SED 's/^.*=//'
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

	states[0]="Submitted"
	states[1]="Running"
	states[2]="Running"
	states[3]="Submitted"
	states[4]="Running"
	states[5]="Submitted"
	states[6]="Unknown"
	states[7]="Submitted"
	states[8]="Running"
	states[9]="Submitted"
	for i in {a..z}; do idchars="$i${idchars}"; done
	for i in {A..Z}; do idchars="$i${idchars}"; done
	for i in {0..9}; do idchars="$i${idchars}"; done
	idchars="${idchars}-_"

	# Register jobs
	for y in {1..9}; do
		printf "Registering testing jobs. Simple, registration only... "
		jobid[${y}0]=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
		printf "(${jobid[${y}0]})"
		test_done

		printf "Simple, state running... "
		jobid[${y}1]=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
		$LB_RUNNING_SH -j ${jobid[${y}1]} > /dev/null 2> /dev/null
		printf "(${jobid[${y}1]})"
		test_done

		printf "Collection, various states... "
		${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application -C -n 3 > coll.reg.$$.out
		jobid[${y}2]=`$SYS_CAT coll.reg.$$.out | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
		printf "${jobid[${y}2]}"
		test_done
		for i in {0..2}; do
			let q=i+3
			jobid[${y}${q}]=`$SYS_CAT coll.reg.$$.out | $SYS_GREP "EDG_WL_SUB_JOBID\[$i\]" | $SYS_SED 's/EDG_WL_SUB_JOBID\[[0-9]*\]="//' | $SYS_SED 's/"$//'`
			printf " - ${jobid[${y}$q]}\n"
		done
		$LB_RUNNING_SH -j ${jobid[${y}4]} > /dev/null 2> /dev/null

		$SYS_RM coll.reg.$$.out

		printf "Grey job, running... "
		uniq=""
		for i in {0..21}; do 
			q=$RANDOM%65;
			q=$q+1;
			uniq="$uniq${idchars:${q}:1}";
		done

		jobid[${y}6]=`echo ${jobid[${y}0]} | $SYS_GREP -o -E "https://.*/"`
		jobid[${y}6]="${jobid[${y}6]}$uniq"
		printf "${jobid[${y}6]}"

		glite-lb-logevent -j ${jobid[${y}6]} -c UI=000000:NS=0000000004:WM=000010:BH=0000000000:JSS=000004:LM=000004:LRMS=000000:APP=000002:LBS=000000 -s LogMonitor -e Running --node="worker node" > /dev/null 2> /dev/null
		test_done

		printf "DAG, various states... "
		${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application -S -n 2 > coll.reg.$$.out
		jobid[${y}7]=`$SYS_CAT coll.reg.$$.out | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
		printf "${jobid[${y}7]}"
		test_done
		for i in {0..1}; do
			let q=i+8
			jobid[${y}${q}]=`$SYS_CAT coll.reg.$$.out | $SYS_GREP "EDG_WL_SUB_JOBID\[$i\]" | $SYS_SED 's/EDG_WL_SUB_JOBID\[[0-9]*\]="//' | $SYS_SED 's/"$//'`
			printf " - ${jobid[${y}$q]}\n"
		done
		$LB_RUNNING_SH -j ${jobid[${y}8]} > /dev/null 2> /dev/null

	done

	printf "Allow 10 s for delivery... "
	sleep 10
	test_done

	printf "Checking states...\n"
	for y in {1..9}; do
		for i in {0..9}; do
			real=`get_state ${jobid[${y}$i]}`
			if [ "$real" == "${states[$i]}" ]; then
				printf "${jobid[${y}$i]}\t$real"
				test_done
			else
				test_failed
				print_error "${jobid[${y}$i]} in state $real, should be ${states[$i]}"
			fi
		done
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
	for y in {1..9}; do
		for i in {0..9}; do
			echo ${jobid[${y}$i]} >> ${joblist}
		done
	done
	${LBPURGE} -j ${joblist} > /dev/null
	test_done

	isThereZombie=0
	printf "Checking states...\n"
	for y in {1..9}; do
		for i in {0..9}; do
			if [ $i -eq 6 ]; then
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
	for y in {1..9}; do
		for i in {0..9}; do
			real=`get_state ${jobid[${y}$i]}`
			if [ "$real" == "${states[$i]}" ]; then
				printf "${jobid[${y}$i]}\t$real"
				test_done
			else
				test_failed
				print_error "${jobid[${y}$i]} in state \"$real\", should be \"${states[$i]}\""
			fi
		done
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

