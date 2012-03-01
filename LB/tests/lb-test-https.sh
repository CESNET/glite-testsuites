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
Script for testing correct job registration

Prerequisities:
   - LB server
   - environment variables set:

     GLITE_LB_SERVER_PORT - if nondefault port (9000) is used
     GLITE_WMS_QUERY_SERVER
     GLITE_WMS_NOTIF_SERVER

Tests called:

    job registration

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
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK $SYS_CURL
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
	SSL_CMD="wget --timeout=60 --no-check-certificate --secure-protocol=SSLv3 --quiet --private-key $X509_USER_PROXY --certificate $X509_USER_PROXY --ca-directory /etc/grid-security/certificates --ca-certificate $X509_USER_PROXY --output-document https.$$.tmp"
	SSL_CLIENT=wget
else
	SSL_CMD="$SYS_CURL --max-time 60 --insecure -3 --silent --key $X509_USER_PROXY --cert $X509_USER_PROXY --capath /etc/grid-security/certificates --output https.$$.tmp"
	SSL_CLIENT=curl
fi
printf "$SSL_CLIENT"
test_done

			# Register job:
			printf "Registering testing job "
			jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`

			if [ -z $jobid  ]; then
				test_failed
				print_error "Failed to register job"
			else
				test_done

				# Get list of jobs
				printf "Evaluating job list... "

				$SSL_CMD https://${GLITE_WMS_QUERY_SERVER}/

				if [ "$?" != "0" ]; then
					test_failed
					print_error "Job list not returned"
				else
					test_done

					printf "Looking up the test job..."

					$SYS_GREP $jobid https.$$.tmp > /dev/null 2> /dev/null

					if [ "$?" != "0" ]; then
						test_failed
						print_error "Test job not found in the list"
					else
						test_done
					fi

					$SYS_RM https.$$.tmp

				fi

				# Get job status
				printf "Evaluating job status listing... "

				$SSL_CMD "${jobid}"

				if [ "$?" != "0" ]; then
					test_failed
					print_error "Job status not returned"
				else
					test_done

					printf "Checking for jobid (verifying content)..."

					$SYS_GREP $jobid https.$$.tmp > /dev/null 2> /dev/null

					if [ "$?" != "0" ]; then
						test_failed
						print_error "JobID not found among data returned"
					else
						test_done
					fi

					$SYS_RM https.$$.tmp

				fi

				#Purge test job
				joblist=$$_jobs_to_purge.txt
				echo $jobid > ${joblist}
				try_purge ${joblist}

			fi

	                # Register notification:
	                printf "Registering notification "

	                notifid=`${LBNOTIFY} new -j ${jobid} | $SYS_GREP "notification ID" | ${SYS_AWK} '{ print $3 }'`
			echo ${LBNOTIFY} new -j ${jobid}
	
        	        if [ -z $notifid ]; then
                	        test_failed 
                        	print_error "Failed to register notification"
	                else
        	                printf "(${notifid}) "
                	        test_done

				# Get notification status
				printf "Evaluating notification status listing... "

				$SSL_CMD "${notifid}"

				if [ "$?" != "0" ]; then
					test_failed
					print_error "Job status not returned"
				else
					test_done

					printf "Checking for jobid (verifying content)..."

					notifunique=`${SYS_ECHO} ${notifid} | ${SYS_SED} 's/^.*NOTIF://'`

					$SYS_GREP $notifunique https.$$.tmp > /dev/null 2> /dev/null

					if [ "$?" != "0" ]; then
						test_failed
						print_error "Notification ID not found among data returned"
					else
						test_done
					fi

					printf "Checking for validity period (to distinguis from job listing)... "
					$SYS_GREP -E "Valid until:</th><td>[0-9 :-]+</td>" https.$$.tmp > /dev/null 2> /dev/null

					if [ "$?" != "0" ]; then
						test_failed
						print_error "Validity period inot listed"
					else
						test_done
					fi

					$SYS_RM https.$$.tmp

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

			printf "Trying excessively long request (Regression into bug #80263)..."
			URL="https://${GLITE_WMS_QUERY_SERVER}/"
			for i in {1..2000}
			do
				URL="${URL}$RANDOM"
			done
			printf "${#URL} characters"

			if [ "$SSL_CLIENT" = "curl" ]; then
				$SSL_CMD -D http.header.dump.$$ $URL
			else
				$SSL_CMD --server-response $URL 2> http.header.dump.$$
			fi
			$SYS_GREP -E "400.*Bad.*Request" http.header.dump.$$ > /dev/null
			if [ "$?" != "0" ]; then
				test_failed
				print_error "Incorrect HTTP header or header dump failed:"
				$SYS_CAT http.header.dump.$$
			else
				test_done
			fi
			$SYS_RM http.header.dump.$$

			printf "Trying request with normal length..."
			URL="https://${GLITE_WMS_QUERY_SERVER}/$RANDOM"
			if [ "$SSL_CLIENT" = "curl" ]; then
				$SSL_CMD -D http.header.dump.$$ $URL
			else
				$SSL_CMD --server-response $URL 2> http.header.dump.$$
			fi
			$SYS_GREP -E "404.*Not.*Found" http.header.dump.$$ > /dev/null
			if [ "$?" != "0" ]; then
				test_failed
				print_error "Incorrect HTTP header or header dump failed:"
				$SYS_CAT http.header.dump.$$
			else
				test_done
			fi
			$SYS_RM http.header.dump.$$

			$SYS_RM https.$$.tmp

			check_srv_version '>=' "2.3"
			if [ $? = 0 ]; then
				printf "Downloading remote configuration... "
				$SSL_CMD https://${GLITE_WMS_QUERY_SERVER}/?configuration > https.$$.tmp
				LineNO=`$SYS_WC -l https.$$.tmp | $SYS_AWK '{ print $1 }' `
				if [ ! "$LineNO" = "0" ]; then
					test_done
					printf "Checking for items... "
					for item in msg_brokers msg_prefixes 
					do
						printf "$item... "
						$SYS_GREP -E "$item.*=" https.$$.tmp > /dev/null
						if [ "$?" = "0" ]; then
							test_done
						else
							test_failed
							print_error "Value $item not returned"
						fi
					done
				else
					test_failed
					print_error "Statistics not returned"
				fi

				printf "Checking statistics... "
				$SSL_CMD https://${GLITE_WMS_QUERY_SERVER}/?stats > https.$$.tmp
				LineNO=`$SYS_WC -l https.$$.tmp | $SYS_AWK '{ print $1 }' `
				if [ ! "$LineNO" = "0" ]; then
					test_done
					printf "Checking for items that should be > 0... "
					for item in "gLite job regs" "Notification regs.*legacy" "HTML accesses" "Plain text accesses"
					do
						printf "$item... "
						ItLine=`$SYS_GREP -E "$item" https.$$.tmp`
						if [ "$?" = "0" ]; then
							ItValue=`$SYS_ECHO $ItLine | $SYS_GREP -o -E -i "<td>[0-9]+</td>" | $SYS_GREP -o -E -i "[0-9]+"`
							printf "$ItValue "
							if [ "$ItValue" != "" -a $ItValue -gt 0 ]; then
								test_done
							else
								test_failed
								print_error "A numeric value greater tha zero should have been returned"
							fi
						else
							test_failed
							print_error "Value $item not returned"
						fi
					done
					printf "Checking stat file location... "
					grep -i -E "<b>[ \t]*WARNING" https.$$.tmp > /dev/null
					if [ $? -eq 0 ]; then
						printf "Files are in tmp!"
						test_warning
					else
						test_done
					fi
				else
					test_failed
					print_error "Statistics not returned"
				fi

				$SYS_RM https.$$.tmp
			else
				printf "Statistics and remote configuration tests... "
				test_skipped
			fi

test_end
}
#} &> $logfile

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK

