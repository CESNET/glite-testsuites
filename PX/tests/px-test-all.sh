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
Script for testing PX and proxyrenewal functions

Prerequisities:
   - PX configured, proxy-renewal installed

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
COMMON=px-common.sh
if [ ! -r ${COMMON} ]; then
	printf "Common definitions '${COMMON}' missing!"
	exit 2
fi
source ${COMMON}
for COMMON in lb-common.sh lb-generate-fake-proxy.sh
do
	if [ ! -r $COMMON ]; then
	        printf "Downloading common definitions '$COMMON'"
	        wget -O $COMMON http://jra1mw.cvs.cern.ch/cgi-bin/jra1mw.cgi/org.glite.testsuites.ctb/LB/tests/$COMMON?view=co > /dev/null
	        if [ ! -r $COMMON ]; then
	                exit 2
	        else
	                test_done
	        fi
	fi
done
source lb-common.sh


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

DEBUG=2

##
#  Starting the test
#####################

{
test_start


# check_binaries
printf "Testing if all binaries are available"
check_binaries curl rm chown openssl sleep voms-proxy-info grep sed glite-proxy-renew wget myproxy-store
if [ $? -gt 0 ]; then
	test_failed
	exit 2
else
	test_done
fi

printf "Testing credentials"
check_credentials_and_generate_proxy
if [ $? != 0 ]; then
        test_end
        exit 2
fi

JOBID=https://fake.job.id/xxx

ORIG_PROXY=`voms-proxy-info | grep -E "^path" | sed 's/^path\s*:\s*//'`
PROXYDN=`voms-proxy-info | grep -E "^identity" | sed 's/^identity\s*:\s*//'`
myproxy-store --certfile $ORIG_PROXY --keyfile $ORIG_PROXY -s localhost -d
myproxy-info -s localhost -l "$PROXYDN"
REGISTERED_PROXY=`glite-proxy-renew -s localhost -f $ORIG_PROXY -j $JOBID start`
printf "\tProxy:\t$ORIG_PROXY\n\tRenew:\t$REGISTERED_PROXY\n"; 
printf "Registered proxy -- "; 
voms-proxy-info -file $REGISTERED_PROXY | grep timeleft; 
printf "sleeping..."; 
sleep 600; 
printf "\nRegistered proxy -- ";
voms-proxy-info -file $REGISTERED_PROXY | grep timeleft; 
printf "Original proxy -- "; 
voms-proxy-info -file $ORIG_PROXY | grep timeleft; 
printf "\nRegistered proxy -- "; 
voms-proxy-info -file $REGISTERED_PROXY -fqan -actimeleft; 
printf "Original proxy -- "; 
voms-proxy-info -file $ORIG_PROXY -fqan -actimeleft; 
printf "\nRegistered proxy -- "; 
voms-proxy-info -file $REGISTERED_PROXY -identity; 
printf "Original proxy -- ";
voms-proxy-info -file $ORIG_PROXY -identity; 
glite-proxy-renew -j $JOBID stop; 
ls $REGISTERED_PROXY 2>&1 | grep 'No such file or directory' > /dev/null && echo OK


test_end
} 

exit $TEST_OK

