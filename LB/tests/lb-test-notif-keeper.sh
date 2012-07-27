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
Script for testing the notif-keeper tool

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

    notif-keeper on various site-notif wording
    registering jobs/sending events
    receiving notifications

EndHelpHeader

	echo "Usage: $progname [OPTIONS]"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -o | --output 'file'   Redirect all output to the 'file' (stdout by default)."
	echo " -t | --text            Format output as plain ASCII text."
	echo " -c | --color           Format output as text with ANSI colours (autodetected by default)."
	echo " -x | --html            Format output as html."
	echo " -f | --file-prefix     Notification file prefix, if other than default."
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
NOTIFPREFIX="/var/tmp/glite-lb-notif"
NL="\n"
while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		"-o" | "--output") shift ; logfile=$1 flag=1 ;;
		"-t" | "--text")  setOutputASCII ;;
		"-c" | "--color") setOutputColor ;;
		"-x" | "--html")  setOutputHTML ; NL="<BR>" ;;
		"-f" | "--file-prefix")  shift ; NOTIFPREFIX=$1 ;;
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

printf "Checking for presence of the notif-keeper tool... "
OLDPATH=$PATH
export PATH=$PATH:/sbin:$GLITE_LOCATION/sbin:$GLITE_LB_LOCATION/sbin
NOTIFKEEPER=`which $LBNOTIFKEEPER`
export PATH=$OLDPATH
if [ ! -f "$NOTIFKEEPER" ]; then
	printf "Not present"
	test_skipped
	exit 0
fi
test_done

printf "Checking for presence of the config file (site-notif.conf)... "
if [ ! -f "/etc/glite-lb/site-notif.conf" ]; then
	printf "/etc/glite-lb/site-notif.conf not found!"
	test_warning
else
	test_done
fi


printf "Checking for presence of the cron script... "
if [ ! -f "/etc/cron.d/glite-lb-notif-keeper" ]; then
	printf "/etc/cron.d/glite-lb-notif-keeper not found!"
	test_warning
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
X509_USER=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^identity" | ${SYS_SED} "s/identity\s*:\s//"`

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
	printf "Reading server configuration"
	$SSL_CMD "https://${GLITE_WMS_QUERY_SERVER}/?configuration"
        if [ "$?" != "0" ]; then
		test_failed
		print_error "Could not read server configuration"
		exit 2
	else
		BROKER=`$SYS_CAT configuration.$$.tmp | $SYS_GREP -E "^msg_brokers=" | $SYS_SED -r 's/^msg_brokers=\s*//' | $SYS_SED -r 's/\s+.*$//' | $SYS_SED 's/tcp:\/\///' | $SYS_SED 's/,.*$//'`
		rm configuration.$$.tmp
		test_done
	fi

	printf "Starting messaging client, listening to broker $BROKER, topic grid.emi.lbtest$$... "
	${LBCMSCLIENT} -o $$_notifications.txt ${BROKER} grid.emi.lbtest$$ > /dev/null &
	recpid=$!

	if [ "$recpid" == "" ]; then
		test_failed
		print_error "Failed to start client"
		exit 2
	fi
	printf "(PID $recpid)"
	test_done

	printf "Giving client time to connect... " 
	sleep 3
	test_done

	printf "Generating fresh site-notif.conf for testing... "
	SITENOTIF=site-notif.$$.conf
	
	printf "test_x$$\t-o $X509_USER -a x-msg://grid.emi.lbtest$$\n#test_y$$\t-T -a x-msg://grid.emi.lbtest$$\n" > $SITENOTIF
	test_done

	printf "Running notif-keeper (notify on all my jobs)... $NL"
	$LBNOTIFKEEPER --file-prefix $NOTIFPREFIX --site-notif $SITENOTIF

	printf "Registering job..."
	jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application 2>&1 | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
	if [ "$jobid" == "" ]; then
		test_failed
		print_error "Failed to register job"
	else
		test_done
	fi

	printf "Waiting for notifications... "
	notif_wait 10 ${jobid} $$_notifications.txt

	printf "Checking number of messages delivered... "
	NOofMESSAGES=`$SYS_GREP -E "Message #[0-9]* Received" $$_notifications.txt | $SYS_WC -l`

	printf "$NOofMESSAGES. Checking if $NOofMESSAGES = 1... "
	cresult=`$SYS_EXPR ${NOofMESSAGES} = 1`

	if [ "$cresult" -eq "1" ]; then
		test_done
	else
		test_failed
		print_error "Received $NOofMESSAGES messages"
	fi

	> $$_notifications.txt

	printf "Modifying site-notif.conf to notify only on state 'running'"
	printf "test_x$$\t-o $X509_USER -c --state running -a x-msg://grid.emi.lbtest$$\n#test_y$$\t-T -a x-msg://grid.emi.lbtest$$\n" > $SITENOTIF
	test_done

	printf "Re-running notif-keeper... $NL"
	$LBNOTIFKEEPER --file-prefix $NOTIFPREFIX --site-notif $SITENOTIF
	
	printf "Registering job..."
	jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application 2>&1 | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
	if [ "$jobid" == "" ]; then
		test_failed
		print_error "Failed to register job"
	else
		test_done
		printf "Sending events resulting in state 'cleared'"
		$LB_CLEARED_SH -j $jobid > /dev/null 2> /dev/null
		test_done
	fi

        printf "Waiting for notifications... "
        notif_wait 10 ${jobid} $$_notifications.txt

        printf "Checking number of messages delivered... "
        NOofMESSAGES=`$SYS_GREP -E "Message #[0-9]* Received" $$_notifications.txt | $SYS_WC -l`

        printf "$NOofMESSAGES. Checking if $NOofMESSAGES = 1... "
        cresult=`$SYS_EXPR ${NOofMESSAGES} = 1`

        if [ "$cresult" -eq "1" ]; then
                test_done
        else
                test_failed
                print_error "Received $NOofMESSAGES messages"
        fi

	printf "Checking if owner DN is present in the message... "
	$SYS_GREP "$X509_USER" $$_notifications.txt >> /dev/null
	if [ $? -eq 0 ]; then
		test_done
	else
		test_failed
		print_error "Expected owner DN not present in message."
	fi

	> $$_notifications.txt

	printf "Modifying site-notif.conf to anonymize states"
	printf "test_x$$\t-o $X509_USER -N -a x-msg://grid.emi.lbtest$$\n#test_y$$\t-T -a x-msg://grid.emi.lbtest$$\n" > $SITENOTIF
	test_done

	printf "Re-running notif-keeper... $NL"
	$LBNOTIFKEEPER --file-prefix $NOTIFPREFIX --site-notif $SITENOTIF

	printf "Registering job..."
	jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application 2>&1 | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
	if [ "$jobid" == "" ]; then
		test_failed
		print_error "Failed to register job"
	else
		test_done
		printf "Sending events resulting in state 'cleared'"
		$LB_CLEARED_SH -j $jobid > /dev/null 2> /dev/null
		test_done
	fi


        printf "Waiting for notifications... "
        notif_wait 10 ${jobid} $$_notifications.txt

        printf "Checking number of messages delivered... "
        NOofMESSAGES=`$SYS_GREP -E "Message #[0-9]* Received" $$_notifications.txt | $SYS_WC -l`

        printf "$NOofMESSAGES. Checking if $NOofMESSAGES >= 1... "
        cresult=`$SYS_EXPR ${NOofMESSAGES} \>= 1`

        if [ "$cresult" -eq "1" ]; then
                test_done
        else
                test_failed
                print_error "Received $NOofMESSAGES messages"
        fi

        printf "Checking if owner DN is present in the message (should not be)... "
        $SYS_GREP "$X509_USER" $$_notifications.txt 
        if [ $? -eq 0 ]; then
                test_failed
                print_error "Owner DN present in message. Should have been anonymized."
        else
		printf "nay"
                test_done
        fi
	

	printf "Modifying site-notif.conf to match on nonsensical owner"
	printf "test_x$$\t-o nemo -a x-msg://grid.emi.lbtest$$\n#test_y$$\t-T -a x-msg://grid.emi.lbtest$$\n" > $SITENOTIF
	test_done

	printf "Re-running notif-keeper... $NL"
	$LBNOTIFKEEPER --file-prefix $NOTIFPREFIX --site-notif $SITENOTIF

	kill $recpid >/dev/null 2>&1

	$SYS_RM $$_notifications.txt $SITENOTIF

test_end
#} &> $logfile
}

if [ $flag -ne 1 ]; then
 	cat $logfile
 	$SYS_RM $logfile
fi
exit $TEST_OK

