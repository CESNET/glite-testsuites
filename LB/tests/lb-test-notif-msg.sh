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
Script for testing notification delivery

Prerequisities:
   - LB server
   - Event logging chain
   - Notification delivery chain (notification interlogger)
   - environment variables set:

     GLITE_LOCATION
     GLITE_WMS_QUERY_SERVER
     GLITE_WMS_LOG_DESTINATION	
     GLITE_WMS_NOTIF_SERVER

Tests called:

    job registration
    notification registration
    logging events
    receiving notifications

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
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK $LBCMSCLIENT $SYS_EXPR $SYS_CURL
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
X509_USER_PROXY=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^path" | ${SYS_SED} "s/path\s*:\s//"`

printf "Using SSL client: "
$SYS_CURL --version | head -n 1 | grep -i NSS/ >/dev/null 2>&1
if [ $? -eq 0 ]; then
        SSL_CMD="wget --no-check-certificate --secure-protocol=SSLv3 --quiet --private-key $X509_USER_PROXY --certificate $X509_USER_PROXY --ca-directory /etc/grid-security/certificates --ca-certificate $X509_USER_PROXY --output-document configuration.$$.tmp"
        SSL_CLIENT=wget
else
        SSL_CMD="$SYS_CURL --insecure -3 --silent --key $X509_USER_PROXY --cert $X509_USER_PROXY --capath /etc/grid-security/certificates --output configuration.$$.tmp"
        SSL_CLIENT=curl
fi
printf "$SSL_CLIENT"
test_done

		# Register job:
		printf "Registering testing job "
		jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application 2>&1 | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`

		if [ -z $jobid ]; then
			test_failed
			print_error "Failed to register job"
		else
			printf "(${jobid}) "
			test_done
		fi

		# Register notification:
		printf "Registering notification "

		notifid=`${LBNOTIFY} new -j ${jobid} -a x-msg://grid.emi.lbtest | $SYS_GREP "notification ID" | ${SYS_AWK} '{ print $3 }'`

		if [ -z $notifid ]; then
			test_failed
			print_error "Failed to register notification"
		else
			printf "(${notifid}) "
			test_done

		        check_srv_version '>=' "2.3"
		        if [ $? -eq 0 ]; then
				printf "Reading server configuration"
				$SSL_CMD "https://${GLITE_WMS_QUERY_SERVER}/?configuration?text"
                               if [ "$?" != "0" ]; then
                                        test_failed
                                        print_error "Could not read server configuration"
                                else
					BROKER=`$SYS_CAT configuration.$$.tmp | $SYS_GREP -E "^msg_brokers=" | $SYS_SED -r 's/^msg_brokers=\s*//' | $SYS_SED -r 's/[, ].*$//' | $SYS_SED 's/tcp:\/\///'`
					rm configuration.$$.tmp
					test_done
				fi

			else
				printf "Reading from config file"
				BROKERLINE=`grep -E "^broker" /etc/glite-lb/msg.conf`
				BROKER=`$SYS_ECHO $BROKERLINE | $SYS_AWK '{print $3}' | $SYS_SED 's/^.*\/\///' | $SYS_SED 's/\///g'`
				test_done
			fi

			if [ ! $BROKER = "" ]; then


				#Start listening for notifications
			
				printf "Checking if client supports output files... "	
				rudver=`${LBCMSCLIENT} | $SYS_GREP '\-o'`
				if [ "$rudver" = "" ]; then
					printf "No. Connecting to broker $BROKER, topic grid.emi.lbtest"
					${LBCMSCLIENT} ${BROKER} grid.emi.lbtest 2>&1 > $$_notifications.txt &
					recpid=$!
				else
					printf "Yes. Connecting to broker $BROKER, topic grid.emi.lbtest"
					${LBCMSCLIENT} -o $$_notifications.txt ${BROKER} grid.emi.lbtest > /dev/null &
					recpid=$!
				fi
					
				test_done

				sleep 2

				printf "Logging events resulting in DONE state... "
				$LB_DONE_SH -j ${jobid} > /dev/null 2> /dev/null
				test_done

				printf "Sleep for 20 seconds to give messages time to deliver... "

				sleep 20
				test_done

				kill -n 15 $recpid

				printf "Checking number of messages delivered... "

				NOofMESSAGES=`$SYS_GREP -E "Message #[0-9]* Received" $$_notifications.txt | $SYS_WC -l`
				
				printf "$NOofMESSAGES. Checking if >= 10... "

				cresult=`$SYS_EXPR ${NOofMESSAGES} \>= 10`

				if [ "$cresult" -eq "1" ]; then
					printf "OK"
					test_done
				else
					test_failed
					print_error "Fewer messages than expected"
				fi

				printf "Checking standard compliance with RFC 4627 "
				./cms-split.pl < $$_notifications.txt
				errout=""
				ok=1
				for file in cms-*.json; do
					out="`./JSON_checker < $file 2>&1`"
					if [ $? -eq 0 ]; then
						printf "."
					else
						printf "!"
						ok=0
						errout="$errout$out"
						cat $file >&2
					fi
					rm $file
				done
				if [ $ok -eq 1 ]; then
					printf " OK"
					test_done
				else
					test_failed
					if [ -n "$errout" ]; then
						print_error "$errout"
					fi
				fi

				$SYS_RM $$_notifications.txt
			else
				printf "Cannot determine broker address"
				test_skipped
			fi



			#Drop notification
			printf "Dropping the test notification (${notifid})"
			dropresult=`${LBNOTIFY} drop ${notifid} 2>&1`
			if [ -z $dropresult ]; then
				test_done
			else
				test_failed
				print_error "Failed to drop notification ${dropresult}"
			fi

			#Purge test job
			joblist=$$_jobs_to_purge.txt
			echo $jobid > ${joblist}
			try_purge ${joblist}

		fi

test_end
#} &> $logfile
}

if [ $flag -ne 1 ]; then
 	cat $logfile
 	$SYS_RM $logfile
fi
exit $TEST_OK

