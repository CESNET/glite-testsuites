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
Script for testing support for logging sandbox transfers

Prerequisities:
   - LB event delivery chain (local logger, interlogger, server)
   - environment variables set:

     GLITE_WMS_QUERY_SERVER - LB server address and port
     GLITE_LB_LOGGER_PORT - if nondefault port (9002) is used 	

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
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK $SYS_CAT
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
		# Register job:
		printf "Registering testing job "

		${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application > sbtestjob.$$.out

		jobid=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
		seqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "EDG_WL_SEQUENCE" | ${SYS_SED} 's/EDG_WL_SEQUENCE=//' | ${SYS_SED} 's/"//g'`

		$SYS_RM sbtestjob.$$.out

		if [ -z $jobid  ]; then
			test_failed
			print_error "Failed to register job"
		else
			test_done

			# Check result
			jobstate=`${LBJOBSTATUS} ${jobid} | $SYS_GREP "state :" | ${SYS_AWK} '{print $3}'`
			printf "Is the testing job ($jobid) in a correct state? $jobstate"

			if [ "${jobstate}" = "Submitted" ]; then
				test_done
			else
				test_failed
				print_error "Job has not been submitted"
			fi

			printf "Registering input SandBox...  "

			$LBREGSANDBOX --jobid $jobid --input --from http://users.machine/path/to/sandbox.file --to file://where/it/is/sandbox.file --sequence $seqcode > sbtestjob.$$.out


			isbjobid=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_LB_ISB_JOBID" | ${SYS_SED} 's/GLITE_LB_ISB_JOBID=//' | ${SYS_SED} 's/"//g'`
			isbseqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_LB_ISB_SEQUENCE" | ${SYS_SED} 's/GLITE_LB_ISB_SEQUENCE=//' | ${SYS_SED} 's/"//g'`
			seqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_WMS_SEQUENCE_CODE" | ${SYS_SED} 's/GLITE_WMS_SEQUENCE_CODE=//' | ${SYS_SED} 's/"//g'`

			$SYS_RM sbtestjob.$$.out

			if [ -z $isbjobid  ]; then
				test_failed
				print_error "Failed to register job"
			else
				printf "$isbjobid"
				test_done

				printf "Registering output SandBox... "
				$LBREGSANDBOX --jobid $jobid --output --from file://where/it/is/sandbox.file2 --to http://users.machine/path/to/sandbox.file2 --sequence $seqcode > sbtestjob.$$.out

				osbjobid=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_LB_OSB_JOBID" | ${SYS_SED} 's/GLITE_LB_OSB_JOBID=//' | ${SYS_SED} 's/"//g'`
				osbseqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_LB_OSB_SEQUENCE" | ${SYS_SED} 's/GLITE_LB_OSB_SEQUENCE=//' | ${SYS_SED} 's/"//g'`

				$SYS_RM sbtestjob.$$.out

				if [ -z $osbjobid  ]; then
					test_failed
					print_error "Failed to register job"
				else
					printf "$osbjobid"
					test_done

					# *************** Input SB transfer -- will be OK ************************************
					printf "Input SB transfer starting... "
					isbseqcode=`$LBLOGEVENT	--source LRMS --jobid $isbjobid --sequence $isbseqcode --event FileTransfer --result START`

					if [ -z $isbseqcode ]; then
						test_failed
						print_error "LogEvent failed"
					else
						test_done
					fi

					sleep 2

					isbjobstate=`$LBJOBSTATUS $isbjobid | $SYS_GREP "state :" | ${SYS_AWK} '{print $3}'`
					printf "Checking state... $isbjobstate"

					if [ "${isbjobstate}" = "Running" ]; then
						test_done
					else
						test_failed
						print_error "'Running' was expected"
					fi

					printf "Input SB transfer finishing... "
					isbseqcode=`$LBLOGEVENT	--source LRMS --jobid $isbjobid --sequence $isbseqcode --event FileTransfer --result OK`

                                        if [ -z $isbseqcode ]; then
                                                test_failed
                                                print_error "LogEvent failed"
                                        else
                                                test_done
                                        fi

                                        sleep 2

                                        isbjobstate=`$LBJOBSTATUS $isbjobid | $SYS_GREP "state :" | ${SYS_AWK} '{print $3}'`
                                        printf "Checking state... $isbjobstate"

                                        if [ "${isbjobstate}" = "Done" ]; then
                                                test_done
                                        else
                                                test_failed
                                                print_error "'Done' was expected"
                                        fi

					# *************** Output SB transfer -- will fail ************************************
					printf "Output SB transfer starting... "
					osbseqcode=`$LBLOGEVENT	--source LRMS --jobid $osbjobid --sequence $osbseqcode --event FileTransfer --result START`

					if [ -z $osbseqcode ]; then
						test_failed
						print_error "LogEvent failed"
					else
						test_done
					fi

					sleep 2

					osbjobstate=`$LBJOBSTATUS $osbjobid | $SYS_GREP "state :" | ${SYS_AWK} '{print $3}'`
					printf "Checking state... $osbjobstate"

					if [ "${osbjobstate}" = "Running" ]; then
						test_done
					else
						test_failed
						print_error "'Running' was expected"
					fi

					printf "Output SB transfer failing... "
					osbseqcode=`$LBLOGEVENT	--source LRMS --jobid $osbjobid --sequence $osbseqcode --event FileTransfer --result FAIL --reason "by design"`

                                        if [ -z $osbseqcode ]; then
                                                test_failed
                                                print_error "LogEvent failed"
                                        else
                                                test_done
                                        fi

                                        sleep 2

                                        osbjobstate=`$LBJOBSTATUS $osbjobid | $SYS_GREP "done_code :" | ${SYS_AWK} '{print $3}'`
                                        printf "Checking Done Code... $osbjobstate"

                                        if [ "${osbjobstate}" = "DONE_CODE_FAILED" ]; then
                                                test_done
                                        else
                                                test_failed
                                                print_error "'DONE_CODE_FAILED' was expected"
					fi

					# ******************** Check relationships *******************************
					printf "Check ISB transfer JobID for computing job... "
					isbjobidreported=`$LBJOBSTATUS $jobid | $SYS_GREP "isb_transfer :" | ${SYS_AWK} '{print $3}'`
					printf "$isbjobidreported"

                                        if [ "$isbjobidreported" = "$isbjobid" ]; then
                                                test_done
                                        else
                                                test_failed
                                                print_error "Not returned or no match"
                                        fi
					printf "Check OSB transfer JobID for computing job... "
					osbjobidreported=`$LBJOBSTATUS $jobid | $SYS_GREP "osb_transfer :" | ${SYS_AWK} '{print $3}'`
					printf "$osbjobidreported"

                                        if [ "$osbjobidreported" = "$osbjobid" ]; then
                                                test_done
                                        else
                                                test_failed
                                                print_error "Not returned or no match"
                                        fi
					printf "Check computing Job ID for ISB... "
					jobidreported=`$LBJOBSTATUS $isbjobid | $SYS_GREP "ft_compute_job :" | ${SYS_AWK} '{print $3}'`
					printf "$jobidreported"

                                        if [ "$jobidreported" = "$jobid" ]; then
                                                test_done
                                        else
                                                test_failed
                                                print_error "Not returned or no match"
                                        fi
				fi
				

			fi

			check_srv_version '>=' "2.4"
			if [ $? -eq 0 ]; then
				test_done

				printf "Querying through EDG_WLL_QUERY_ATTR_JOB_TYPE... input SB... "
				printf "job_type=file_transfer\njobid<>\"https://$GLITE_WMS_QUERY_SERVER/none\"\n" > query_input.$$.txt
				${LBQUERYEXT} -C -m $GLITE_WMS_QUERY_SERVER -i query_input.$$.txt > query_output.$$.txt 2> /dev/null
				$SYS_GREP $isbjobid query_output.$$.txt > /dev/null 2> /dev/null
				if [ $? -gt 0 ]; then test_failed && print_error "Test job not included among results" && cat query_output.$$.txt; else test_done; fi
				printf "output SB... "
				$SYS_GREP $osbjobid query_output.$$.txt > /dev/null 2> /dev/null
				if [ $? -gt 0 ]; then test_failed && print_error "Test job not included among results" && cat query_output.$$.txt; else test_done; fi

				printf "Querying through EDG_WLL_QUERY_ATTR_JOB_TYPE... negative... input SB... "
				printf "job_type<>file_transfer\njobid<>\"https://$GLITE_WMS_QUERY_SERVER/none\"\n" > query_input.$$.txt
				${LBQUERYEXT} -C -m $GLITE_WMS_QUERY_SERVER -i query_input.$$.txt > query_output.$$.txt 2> /dev/null
				$SYS_GREP $isbjobid query_output.$$.txt > /dev/null 2> /dev/null
				if [ $? -eq 0 ]; then test_failed && print_error "Test job included among results" && cat query_output.$$.txt; else test_done; fi
				printf "output SB... "
				$SYS_GREP $osbjobid query_output.$$.txt > /dev/null 2> /dev/null
				if [ $? -eq 0 ]; then test_failed && print_error "Test job included among results" && cat query_output.$$.txt; else test_done; fi

				${SYS_RM} query_input.$$.txt query_output.$$.tx
			else
				test_skipped
			fi


			#Purge test job
			joblist=$$_jobs_to_purge.txt
			echo $jobid > ${joblist}
			echo $isbjobid >> ${joblist}
			echo $osbjobid >> ${joblist}
			try_purge ${joblist}

		fi

		#******************************* Test sandbox collection *********************************

	        #check_srv_version '>=' "2.2"
	        #if [ $? = 0 ]; then
                	test_done


			# Register job:
			printf "Registering testing job "

			${LBJOBREG} -m ${GLITE_WMS_QUERY_SERVER} -s application > sbtestjob.$$.out

			jobid=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "new jobid" | ${SYS_AWK} '{ print $3 }'`
			seqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "EDG_WL_SEQUENCE" | ${SYS_SED} 's/EDG_WL_SEQUENCE=//' | ${SYS_SED} 's/"//g'`

			$SYS_RM sbtestjob.$$.out

			if [ -z $jobid  ]; then
				test_failed
				print_error "Failed to register job"
			else
				test_done
				
				# register sandbox collection 

				printf "Registering input SandBox collection...  "

				$LBREGSANDBOX --jobid $jobid --input --from http://users.machine/path/to/sandbox.file --to file://where/it/is/sandbox.file --sequence $seqcode -n 2 > sbtestjob.$$.out 2> sbtestjob.$$.err

				$SYS_GREP "invalid option -- n" sbtestjob.$$.err > /dev/null

				if [ $? -eq 0 ]; then
					printf "Capability not detected..."
					test_skipped
				else

					isbjobid=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_LB_ISB_JOBID" | ${SYS_SED} 's/GLITE_LB_ISB_JOBID=//' | ${SYS_SED} 's/"//g'`
					isbseqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_LB_ISB_SEQUENCE" | ${SYS_SED} 's/GLITE_LB_ISB_SEQUENCE=//' | ${SYS_SED} 's/"//g'`
					seqcode=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "GLITE_WMS_SEQUENCE_CODE" | ${SYS_SED} 's/GLITE_WMS_SEQUENCE_CODE=//' | ${SYS_SED} 's/"//g'`
					isbsubjobid0=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "EDG_WL_SUB_JOBID\[0\]" | ${SYS_SED} 's/EDG_WL_SUB_JOBID\[0\]=//' | ${SYS_SED} 's/"//g'`
					isbsubjobid1=`$SYS_CAT sbtestjob.$$.out | $SYS_GREP "EDG_WL_SUB_JOBID\[1\]" | ${SYS_SED} 's/EDG_WL_SUB_JOBID\[1\]=//' | ${SYS_SED} 's/"//g'`

					printf "Subjobs: " $isbsubjobid0 $isbsubjobid1

					$SYS_RM sbtestjob.$$.out

					if [ -z $isbjobid  ]; then
						test_failed
						print_error "Failed to register job"
					else
						printf "$isbjobid"
						test_done

						# Prepare list for future purge

						joblist=$$_jobs_to_purge.txt
						echo $jobid > ${joblist}
						echo $isbjobid >> ${joblist}
						echo $isbsubjobid0 >> ${joblist}
						echo $isbsubjobid1 >> ${joblist}

						sleep 2

						# Check relations

						printf "Check ISB transfer JobID for computing job... "
						isbjobidreported=`$LBJOBSTATUS $jobid | $SYS_GREP -m 1 "isb_transfer :" | ${SYS_AWK} '{print $3}'`
						printf "$isbjobidreported"

						if [ "$isbjobidreported" = "$isbjobid" ]; then
							test_done
						else
							test_failed
							print_error "Not returned or no match"
						fi

						printf "Check computing Job ID for ISB... "
						jobidreported=`$LBJOBSTATUS $isbjobid | $SYS_GREP -m 1 "ft_compute_job :" | ${SYS_AWK} '{print $3}'`
						printf "$jobidreported"

						if [ "$jobidreported" = "$jobid" ]; then
							test_done
						else
							test_failed
							print_error "Not returned or no match"
						fi

						printf "Check computing Job ID for subjob 0... "
						jobidreported=`$LBJOBSTATUS $isbsubjobid0 | $SYS_GREP "ft_compute_job :" | ${SYS_AWK} '{print $3}'`
						printf "$jobidreported"

						if [ "$jobidreported" = "$jobid" ]; then
							test_done
						else
							test_failed
							print_error "Not returned or no match"
						fi

						printf "Check transfer Job ID for subjob 0... "
						jobidreported=`$LBJOBSTATUS $isbsubjobid0 | $SYS_GREP "parent_job :" | ${SYS_AWK} '{print $3}'`
						printf "$jobidreported"

						if [ "$jobidreported" = "$isbjobid" ]; then
							test_done
						else
							test_failed
							print_error "Not returned or no match"
						fi


						# Check states
						
						isbjobstate=`$LBJOBSTATUS $isbjobid | $SYS_GREP -m 1 "state :" | ${SYS_AWK} '{print $3}'`
						printf "Checking state of $isbjobid... $isbjobstate"

						if [ "${isbjobstate}" = "Submitted" ]; then
							test_done
						else
							test_failed
							print_error "'Submitted' was expected"
						fi

						isbjobstate=`$LBJOBSTATUS $isbsubjobid0 | $SYS_GREP "state :" | ${SYS_AWK} '{print $3}'`
						printf "Checking state of $isbsubjobid0... $isbjobstate"

						if [ "${isbjobstate}" = "Submitted" ]; then
							test_done
						else
							test_failed
							print_error "'Submitted' was expected"
						fi

						isbjobstate=`$LBJOBSTATUS $isbsubjobid1 | $SYS_GREP "state :" | ${SYS_AWK} '{print $3}'`
						printf "Checking state of $isbsubjobid1... $isbjobstate"

						if [ "${isbjobstate}" = "Submitted" ]; then
							test_done
						else
							test_failed
							print_error "'Submitted' was expected"
						fi

						# log src/dest for subjob 1
						printf "Logging source and destination for subjob 1"
						isbseqcode=`$LBLOGEVENT --source LRMS --jobid $isbsubjobid1 --sequence $isbseqcode --event FileTransferRegister --src  http://users.machine/path/to/sandbox.file.1 --dest file://where/it/is/sandbox.file.1`
						if [ -z $isbseqcode ]; then
                                                        test_failed
                                                        print_error "LogEvent failed"
                                                else
                                                        test_done
                                                fi

						# Check source
						sleep 10

						isbsubjobsrc1=`$LBJOBSTATUS $isbsubjobid1 | $SYS_GREP "ft_src :" | ${SYS_AWK} '{print $3}'`

						printf "Checking source of $isbsubjobid1... $isbsubjobsrc1"

						if [ "${isbsubjobsrc1}" = "http://users.machine/path/to/sandbox.file.1" ]; then
							test_done
						else
							test_failed
							printf "http://users.machine/path/to/sandbox.file.1 was expected"
						fi

						# Check destination

						isbsubjobdest1=`$LBJOBSTATUS $isbsubjobid1 | $SYS_GREP "ft_dest :" | ${SYS_AWK} '{print $3}'`

                                                printf "Checking destination of $isbsubjobid1... $isbsubjobdest1"

                                                if [ "${isbsubjobdest1}" = "file://where/it/is/sandbox.file.1" ]; then
                                                        test_done
                                                else
                                                        test_failed
                                                        printf "file://where/it/is/sandbox.file.1 was expected"
                                                fi


						# log START for subjob 1
						printf "Subjob 1 transfer starting... "
						isbseqcode=`$LBLOGEVENT --source LRMS --jobid $isbsubjobid1 --sequence $isbseqcode --event FileTransfer --result START`

						if [ -z $isbseqcode ]; then
							test_failed
							print_error "LogEvent failed"
						else
							test_done
						fi

						# Check states
						sleep 2
						
						isbjobstate=`$LBJOBSTATUS $isbjobid | $SYS_GREP -m 1 "state :" | ${SYS_AWK} '{print $3}'`
						printf "Checking state of $isbjobid... $isbjobstate"

						if [ "${isbjobstate}" = "Running" ]; then
							test_done
						else
							test_failed
							print_error "'Running' was expected"
						fi

						isbjobstate=`$LBJOBSTATUS $isbsubjobid1 | $SYS_GREP "state :" | ${SYS_AWK} '{print $3}'`
						printf "Checking state of $isbsubjobid1... $isbjobstate"

						if [ "${isbjobstate}" = "Running" ]; then
							test_done
						else
							test_failed
							print_error "'Running' was expected"
						fi

						# log OK for subjob 1
						printf "Subjob 1 transfer ending... "
						isbseqcode=`$LBLOGEVENT --source LRMS --jobid $isbsubjobid1 --sequence $osbseqcode --event FileTransfer --result OK`

						if [ -z $isbseqcode ]; then
							test_failed
							print_error "LogEvent failed"
						else
							test_done
						fi

						# Check states
						sleep 2

						isbjobstate=`$LBJOBSTATUS $isbjobid | $SYS_GREP -m 1 "state :" | ${SYS_AWK} '{print $3}'`
						printf "Checking state of $isbjobid... $isbjobstate"

						if [ "${isbjobstate}" = "Waiting" ]; then
							test_done
						else
							test_failed
							print_error "'Waiting' was expected"
						fi

						isbjobstate=`$LBJOBSTATUS $isbsubjobid1 | $SYS_GREP "state :" | ${SYS_AWK} '{print $3}'`
						printf "Checking state of $isbsubjobid1... $isbjobstate"

						if [ "${isbjobstate}" = "Done" ]; then
							test_done
						else
							test_failed
							print_error "'Done' was expected"
						fi

						isbjobstate=`$LBJOBSTATUS $isbsubjobid1 | $SYS_GREP "done_code :" | ${SYS_AWK} '{print $3}'`
						printf "Checking Done Code... $isbjobstate"

						if [ "${isbjobstate}" = "DONE_CODE_OK" ]; then
							test_done
						else
							test_failed
							print_error "'DONE_CODE_OK' was expected"
						fi

						# log src/dest for subjob 0
                                                printf "Logging source and destination for subjob 0"
                                                isbseqcode=`$LBLOGEVENT --source LRMS --jobid $isbsubjobid0 --sequence $isbseqcode --event FileTransferRegister --src  http://users.machine/path/to/sandbox.file.0 --dest file://where/it/is/sandbox.file.0`
                                                if [ -z $isbseqcode ]; then
                                                        test_failed
                                                        print_error "LogEvent failed"
                                                else
                                                        test_done
                                                fi

                                                # Check source
                                                sleep 10

                                                isbsubjobsrc0=`$LBJOBSTATUS $isbsubjobid0 | $SYS_GREP "ft_src :" | ${SYS_AWK} '{print $3}'`

                                                printf "Checking source of $isbsubjobid0... $isbsubjobsrc0"

                                                if [ "${isbsubjobsrc0}" = "http://users.machine/path/to/sandbox.file.0" ]; then
                                                        test_done
                                                else
                                                        test_failed
                                                        printf "http://users.machine/path/to/sandbox.file.1 was expected"
                                                fi

						# Check destination

						isbsubjobdest0=`$LBJOBSTATUS $isbsubjobid0 | $SYS_GREP "ft_dest :" | ${SYS_AWK} '{print $3}'`

                                                printf "Checking destination of $isbsubjobid0... $isbsubjobdest0"

                                                if [ "${isbsubjobdest0}" = "file://where/it/is/sandbox.file.0" ]; then
                                                        test_done
                                                else    
                                                        test_failed 
                                                        printf "file://where/it/is/sandbox.file.0 was expected"
                                                fi

						# log START for subjob 0
						printf "Subjob 0 transfer starting... "
						isbseqcode=`$LBLOGEVENT --source LRMS --jobid $isbsubjobid0 --sequence $osbseqcode --event FileTransfer --result START` 

						if [ -z $isbseqcode ]; then
							test_failed
							print_error "LogEvent failed"
						else
							test_done
						fi

						# Check states
						sleep 2

						isbjobstate=`$LBJOBSTATUS $isbjobid | $SYS_GREP -m 1 "state :" | ${SYS_AWK} '{print $3}'`
						printf "Checking state of $isbjobid... $isbjobstate"

						if [ "${isbjobstate}" = "Running" ]; then
							test_done
						else
							test_failed
							print_error "'Running' was expected"
						fi

						isbjobstate=`$LBJOBSTATUS $isbsubjobid0 | $SYS_GREP "state :" | ${SYS_AWK} '{print $3}'`
						printf "Checking state of $isbsubjobid0... $isbjobstate"

						if [ "${isbjobstate}" = "Running" ]; then
							test_done
						else
							test_failed
							print_error "'Running' was expected"
						fi

						# log FAIL for subjob 0
						printf "Subjob 0 transfer ending... "
						isbseqcode=`$LBLOGEVENT --source LRMS --jobid $isbsubjobid0 --sequence $osbseqcode --event FileTransfer --result FAIL`

						if [ -z $isbseqcode ]; then
							test_failed
							print_error "LogEvent failed"
						else
							test_done
						fi

						# Check states
						sleep 2

						isbjobstate=`$LBJOBSTATUS $isbjobid | $SYS_GREP -m 1 "state :" | ${SYS_AWK} '{print $3}'`
						printf "Checking state of $isbjobid... $isbjobstate"

						if [ "${isbjobstate}" = "Waiting" ]; then
							test_done
						else
							test_failed
							print_error "'Waiting' was expected"
						fi

						isbjobstate=`$LBJOBSTATUS $isbsubjobid0 | $SYS_GREP "state :" | ${SYS_AWK} '{print $3}'`
						printf "Checking state of $isbsubjobid0... $isbjobstate"

						if [ "${isbjobstate}" = "Done" ]; then
							test_done
						else
							test_failed
							print_error "'Done' was expected"
						fi

						isbjobstate=`$LBJOBSTATUS $isbsubjobid0 | $SYS_GREP "done_code :" | ${SYS_AWK} '{print $3}'`
						printf "Checking Done Code... $isbjobstate"

						if [ "${isbjobstate}" = "DONE_CODE_FAILED" ]; then
							test_done
						else
							test_failed
							print_error "'DONE_CODE_FAILED' was expected"
						fi

						# START and OK subjob 0

						printf "Subjob 0 starting and ending..."
						isbseqcode=`$LBLOGEVENT --source LRMS --jobid $isbsubjobid0 --sequence $osbseqcode --event FileTransfer --result START`
						isbseqcode=`$LBLOGEVENT --source LRMS --jobid $isbsubjobid0 --sequence $osbseqcode --event FileTransfer --result OK`

						# Check states
						sleep 2

						isbjobstate=`$LBJOBSTATUS $isbjobid | $SYS_GREP -m 1 "state :" | ${SYS_AWK} '{print $3}'`
						printf "Checking state of $isbjobid... $isbjobstate"

						if [ "${isbjobstate}" = "Done" ]; then
							test_done
						else
							test_failed
							print_error "'Done' was expected"
						fi

						isbjobstate=`$LBJOBSTATUS $isbjobid | $SYS_GREP -m 1 "done_code :" | ${SYS_AWK} '{print $3}'`
						printf "Checking Done Code... $isbjobstate"

						if [ "${isbjobstate}" = "DONE_CODE_OK" ]; then
							test_done
						else
							test_failed
							print_error "'DONE_CODE_OK' was expected"
						fi

						isbjobstate=`$LBJOBSTATUS $isbsubjobid0 | $SYS_GREP "state :" | ${SYS_AWK} '{print $3}'`
						printf "Checking state of $isbsubjobid... $isbjobstate"

						if [ "${isbjobstate}" = "Done" ]; then
							test_done
						else
							test_failed
							print_error "'Done' was expected"
						fi

						isbjobstate=`$LBJOBSTATUS $isbsubjobid0 | $SYS_GREP "done_code :" | ${SYS_AWK} '{print $3}'`
						printf "Checking Done Code... $isbjobstate"

						if [ "${isbjobstate}" = "DONE_CODE_OK" ]; then
							test_done
						else
							test_failed
							print_error "'DONE_CODE_OK' was expected"
						fi

						try_purge ${joblist}

						printf "Check if purging was allowed..."
						$LBJOBSTATUS $jobid > /dev/null 2>/dev/null
						if [ $? -gt 0 ]; then
							test_done
							printf "Test if SB Collection was purged..."
							$LBJOBSTATUS $isbjobid > /dev/null 2>/dev/null
							if [ $? -gt 0 ]; then
								test_done
							else
								test_failed
							fi

							printf "Test if SB Collection subjob was purged..."
							$LBJOBSTATUS $isbsubjobid0 > /dev/null 2>/dev/null
							if [ $? -gt 0 ]; then
								test_done
							else
								test_failed
							fi
							
						else
							test_skipped								
						fi
					fi
				fi
				$SYS_RM sbtestjob.$$.err
			fi
		#else
		#	printf "SB colection capability not detected..."
		#	test_skipped
		#fi

test_end

#} &> $logfile

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK
}
