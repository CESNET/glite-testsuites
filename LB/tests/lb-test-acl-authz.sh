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
     X509_USER_PROXY_BOB
     set TEST_TAG_ACL=yes if you want to test ACL with TAGs

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


check_credentials()
{
	my_GRIDPROXYINFO=${GRIDPROXYINFO}
	if [ "$1" != "" ]; then
		my_GRIDPROXYINFO="${GRIDPROXYINFO} -f $1"
	fi

	timeleft=`${my_GRIDPROXYINFO} | ${SYS_GREP} -E "^timeleft" | ${SYS_SED} "s/timeleft\s*:\s//"`

	if [ "$timeleft" = "" ]; then
        	print_error "No credentials"
		return 1
	fi
        if [ "$timeleft" = "0:00:00" ]; then
          	print_error "Credentials expired"
		return 1
	fi
	return 0
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

test_tag_acl=${TEST_TAG_ACL:-"no"}

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
	check_credentials_and_generate_proxy
	if [ $? != 0 ]; then
		test_end
		exit 2
	fi

	printf "Testing snd proxy certificate"
	if [ "$X509_USER_PROXY_BOB" = "" ]; then
		test_failed
		print_error "\$X509_USER_PROXY_BOB must be set"
		break
	fi
	check_credentials $X509_USER_PROXY_BOB
	if [ $? -ne 0 ]; then
		test_failed
		break
	fi
	test_done

	printf "Testing Tags permissions "
	if [ "$test_tag_acl" != "yes" ]; then
        	test_skipped
	else
		test_done
	fi

	identity=`${GRIDPROXYINFO} -f $X509_USER_PROXY_BOB| ${SYS_GREP} -E "^identity" | ${SYS_SED} "s/identity\s*:\s//"`

	# Register job:
	printf "Registering testing job "
	jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`

	if [ -z $jobid  ]; then
		test_failed
		print_error "Failed to register job"
		break
	fi
	test_done

	printf "Checking not-allowed access"
#try unauthorized read
	X509_USER_PROXY=$X509_USER_PROXY_BOB $LBJOBSTATUS $jobid 2>&1 >/dev/null| grep -E "edg_wll_JobStatus: Operation not permitted" > /dev/null
	if [ "$?" != "0" ]; then
		test_failed
		print_error "Ungranted READ access allowed!"
		break
	fi

#try unauthorized tagging
	X509_USER_PROXY=$X509_USER_PROXY_BOB $LBLOGEVENT -e UserTag -s Application -j $jobid --name "hokus" --value "pokus" > /dev/null
	if [ $? -ne 0 ]; then
		test_failed
		print_error "Sending UserTag failed"
		break
	fi
#	sleep 10

	res=`$LBJOBSTATUS $jobid 2>/dev/null`
	if [ $? -ne 0 ]; then
		test_failed
		print_error "Server doesn't respond"
		break
	fi
	echo $res | grep "hokus = \"pokus\"" > /dev/null
	if [ $? -eq 0 ]; then
		test_failed
		print_error "Adding UserTag allowed"
		break
	fi
	test_done

	printf "Changing ACL setting "
	perms="READ"
	[ "$test_tag_acl" = "yes" ] && perms="$perms TAG"
	res=0
	for p in $perms; do
		$LBLOGEVENT -e ChangeACL -s UserInterface -p -j $jobid --user_id "$identity" --user_id_type DN --permission $p --permission_type ALLOW --operation ADD > /dev/null
		if [ $? -ne 0 ]; then
			print_error "Adding $p permission to ACL failed"
			res=1
		fi
	done
	if [ $res -ne 0 ]; then
		test_failed
		break
	fi
	test_done

	printf "Checking allowed access "
#try querying status
	X509_USER_PROXY=$X509_USER_PROXY_BOB $LBJOBSTATUS $jobid 2>/dev/null| grep "^state : Submitted" > /dev/null
	if [ $? -ne 0 ]; then
		test_failed
		print_error "ACL permission doesn't work"
		break
	fi

#try adding a usertag
	if [ "$test_tag_acl" = "yes" ]; then
		X509_USER_PROXY=$X509_USER_PROXY_BOB $LBLOGEVENT -e UserTag -s Application -j $jobid --name "hokus" --value "pokus" > /dev/null
		if [ $? -ne 0 ]; then
			test_failed
			print_error "Sending UserTag failed"
			break
		fi

	#	sleep 10

		res=`$LBJOBSTATUS $jobid 2>/dev/null`
		if [ $? -ne 0 ]; then
			test_failed
			print_error "Server doesn't respond"
			break
		fi
		echo $res | grep "hokus = \"pokus\"" > /dev/null
		if [ $? -ne 0 ]; then
			test_failed
			print_error "Adding UserTag not allowed"
			break
		fi
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

