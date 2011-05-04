#!/bin/bash
#
# Copyright (c) Members of the EGEE Collaboration. 2004-2010.
# See http://www.eu-egee.org/partners/ for details on the copyright holders.
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
Script for testing correct interpretation of ChangeACL events

Prerequisities:
   - LB server, logger, interlogger
   - environment variables set:

     GLITE_WMS_QUERY_SERVER
     set TEST_TAG_ACL=yes if the you want to test ACL with TAGs


Tests called:

    job registration
    sending a ChangeACL-type event
    chcking result

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

change_acl()
{
	jobid=$1; op=$2; perm=$3; id=$4

	$LBLOGEVENT -e ChangeACL -s UserInterface -p -j "$jobid" --user_id "$id" --user_id_type DN --permission "$perm" --permission_type ALLOW --operation "$op" > /dev/null
	res=$?
	if [ $res -ne 0 ]; then
		print_error "Changing ACL ($op $perm) failed"
	fi
	return $res
}

##
#  Starting the test
#####################

identity="ThisIsJustATestingIdentity"

{
test_start

CONT="yes"
while [ "$CONT" = "yes" ]; do
	CONT="no"

	# check_binaries
	printf "Testing if all binaries are available"
	check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK $LBLOGEVENT $LBJOBREG
	if [ $? -gt 0 ]; then
		test_failed
		break
	fi
	test_done

	printf "Testing credentials"
	timeleft=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^timeleft" | ${SYS_SED} "s/timeleft\s*:\s//"`
	if [ "$timeleft" = "" ]; then
        	test_failed
        	print_error "No credentials"
		break
	fi

        if [ "$timeleft" = "0:00:00" ]; then
                test_failed
                print_error "Credentials expired"
		break
	fi
	test_done

        check_srv_version '>=' "2.2"
        if [ $? -gt 0 ]; then
		test_tag_acl="no"
		test_done
        else
		test_tag_acl="yes"
		test_done
        fi

	printf "Testing Tags permissions... "
	if [ "$test_tag_acl" != "yes" ]; then
		printf "Capability not detected..."
        	test_skipped
	else
		test_done
	fi

	# Register job:
	printf "Registering testing job "
	jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
	if [ -z $jobid  ]; then
		test_failed
		print_error "Failed to register job"
		break
	fi
	printf " $jobid"
	test_done

	printf "Changing ACL..."
	change_acl "$jobid" "ADD" "READ" $identity
	if [ $? -ne 0 ]; then
		test_failed
		break;
	fi

	if [ "$test_tag_acl" = "yes" ]; then
		change_acl "$jobid" "ADD" "TAG" $identity
		if [ $? -ne 0 ]; then
			test_failed
			break
		fi
	fi
	test_done

	printf "Checking ACL for new values... "
	ops="read"
	[ "$test_tag_acl" = "yes" ] && ops="$ops write"
	res=0
	for operation in $ops; do
		$LBJOBSTATUS $jobid | grep -E "^acl :.*<entry><cred><auri>dn:${identity}</auri></cred><allow><${operation}/></allow></entry>" > /dev/null
		if [ $? -ne 0 ]; then
			res=1
		fi
	done
	if [ $res -ne 0 ]; then
		test_failed
		print_error "ACL not modified properly"
		break;
	fi
	test_done


	printf "Removing ACL entries..."
	perms="READ"
	[ "$test_tag_acl" = "yes" ] && perms="$perms TAG"
	res=0
	for p in $perms; do
		change_acl "${jobid}" "REMOVE" $p $identity
		if [ $? -ne 0 ]; then
			res=1
		fi
	done
	if [ $res -ne 0 ]; then
		test_failed
		break;
	fi

	$LBJOBSTATUS $jobid | grep -E "^acl :<?xml version="1.0"?><gacl version="0.9.0"></gacl>$" > /dev/null
	if [ $res -ne 0 ]; then
		test_failed
		print_error "Entries not removed properly"
	fi
	test_done

		
	#Purge test job
	joblist=$$_jobs_to_purge.txt
	echo $jobid > ${joblist}
	try_purge ${joblist}

done

test_end
} &> $logfile

if [ $flag -ne 1 ]; then
 	cat $logfile
 	$SYS_RM $logfile
fi
exit $TEST_OK

