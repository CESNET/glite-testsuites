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
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK $LBJOBREG $LBWSJOBSTATUS $LBWSJOBLOG $SYS_HOSTNAME
if [ $? -gt 0 ]; then
	test_failed
else
	test_done
fi

printf "Testing credentials"

timeleft=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^timeleft" | ${SYS_SED} "s/timeleft\s*:\s//"`

if [ "$timeleft" = "" ]; then
        test_failed
        print_error "No credentials"
else
        if [ "$timeleft" = "0:00:00" ]; then
                test_failed
                print_error "Credentials expired"
        else
                test_done

		# Register job:
		printf "Registering testing job "
		jobid=`${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`

		if [ -z $jobid  ]; then
			test_failed
			print_error "Failed to register job"
		else
			test_done

			servername=`echo ${GLITE_WMS_QUERY_SERVER} | ${SYS_SED} "s/:.*//"`
			printf "WS interface to query: ${servername}:${GLITE_LB_SERVER_WPORT}\n"

			printf "Has the job ($jobid) been submitted?"

			${LBWSJOBSTATUS} -j ${jobid} -m ${servername}:${GLITE_LB_SERVER_WPORT} | $SYS_GREP "<state>SUBMITTED</state>" >> /dev/null
	                if [ $? = 0 ]; then
				test_done
			else
				test_failed
				print_error "Job has not been submitted"
			fi

			#(regresion-test Savannah Bug 77002)
			printf "Checking if doneCode unset for job not yet done... "
                	check_srv_version '>=' "2.2"
	                if [ $? = 0 ]; then
				doneCode=`${LBWSJOBSTATUS} -m ${servername}:${GLITE_LB_SERVER_WPORT} -j ${jobid} | ${SYS_GREP} status | ${SYS_GREP} doneCode | ${SYS_SED} 's/^.*<doneCode>//' | ${SYS_SED} 's/<\/doneCode>.*$//'`

				printf "($doneCode)"

				if [ "$doneCode" == "" ]; then
					test_done
				else
					test_failed
					print_error "doneCode value $doneCode unexpected"
				fi
			else
				test_skipped
			fi

			printf "Is it possible to retrieve events?"

			${LBWSJOBLOG} -j ${jobid} -m ${servername}:${GLITE_LB_SERVER_WPORT} | $SYS_GREP "<RegJob>" >> /dev/null
	                if [ $? = 0 ]; then
				test_done
			else
				test_failed
				print_error "Job has not been submitted"
			fi

			printf "Is it possible to retrieve AGU activity info?"
			check_binaries ${LB4AGUACTINFO} ${LB4AGUACTSTATUS}
			if [ $? -gt 0 ]; then
				test_missed
			else
				${LB4AGUACTINFO} -j ${jobid} -m ${servername}:${GLITE_LB_SERVER_WPORT} | $SYS_GREP "${jobid}" >> /dev/null
		                if [ $? = 0 ]; then
					test_done
				else
					test_failed
					print_error "Job Activity Info returned"
				fi

				printf "Does AGU activity status return correct state?"

				${LB4AGUACTSTATUS} -j ${jobid} -m ${servername}:${GLITE_LB_SERVER_WPORT} | $SYS_GREP "urn:org.glite.lb:Submitted" >> /dev/null
		                if [ $? = 0 ]; then
					test_done
				else
					test_failed
					print_error "Reported status is Running"
				fi
			fi

			#Purge test job
			joblist=$$_jobs_to_purge.txt
			echo $jobid > ${joblist}
			try_purge ${joblist}

		fi

		printf "Getting server version... "
                servername=`echo ${GLITE_WMS_QUERY_SERVER} | ${SYS_SED} "s/:.*//"`
                wsglservver=`$LBWSGETVERSION -m ${servername}:${GLITE_LB_SERVER_WPORT} | $SYS_SED 's/^.*Server version:\s*//'`
                if [ "$wsglservver" == "" ]; then
	                test_failed
                else
        	        printf "$wsglservver"
                        test_done
                fi

		printf "Getting WS interface version... "
               	check_srv_version '>=' "2.2"
                if [ $? = 0 ]; then
	                wsglifver=`$LBWSGETVERSION -i -m ${servername}:${GLITE_LB_SERVER_WPORT} | $SYS_SED 's/^.*Interface version:\s*//'`
        	        if [ "$wsglifver" == "" ]; then
	        	        test_failed
	                else
        		        printf "$wsglifver"
                	        test_done
	                fi
		else
			test_skipped
		fi

		printf "Check if test runs on server... "
		localname=`$SYS_HOSTNAME -f`

                if [ "$servername" == "$localname" ]; then
			printf "Get rpm version... "
			rpmversion=`$SYS_RPM -qi glite-lb-ws-interface | $SYS_GREP -E "^Version" | $SYS_SED 's/^Version\s*:\s*//' | $SYS_SED 's/\s.*$//'`

	                if [ "$rpmversion" == "" ]; then
				printf "Unable to detect rpm version"
        	                test_skipped
	                else
                	        printf "$rpmversion"
        	                test_done

				printf "Comparing versions ($wsglifver == $rpmversion)... "

		                if [ "$wsglifver" == "$rpmversion" ]; then
                		        test_done
		                else
		                        test_failed
					print_error "Reported version differs from that indicated by RPM"
		                fi
	                fi
		else
			printf "No"
                        test_skipped
                fi
	fi
fi

test_end
#} &> $logfile
}

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK

