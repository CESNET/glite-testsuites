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
This script logs to an indicated server, downloads the L&B test suite and executes it

Prerequisities:
   - LB server (hostname given as a cmdline argument)
   - Valid proxy certificate (will be imported and used in testing)

Tests called:

	The full L&B Functional Test Suite

EndHelpHeader

	echo "Usage: $progname [OPTIONS] hostname"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -P | --no-proxy        Do not copy existing user proxy."
	echo " hostname               L&B server to use for testing."
}

# read common definitions and functions
COMMON=lb-common.sh
if [ ! -r ${COMMON} ]; then
	printf "Common definitions '${COMMON}' missing!"
	exit 2
fi
source ${COMMON}
COMMONTESTBEDS=lb-common-testbeds.sh
if [ ! -r ${COMMONTESTBEDS} ]; then
	printf "Common definitions '${COMMONTESTBEDS}' missing!"
	exit 2
fi
source ${COMMONTESTBEDS}

COPYPROXY=1

#logfile=$$.tmp
#flag=0
while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		"-P" | "--no-proxy") COPYPROXY=0 ;;
		*) remotehost=$1 
			shift
			outformat=$1
			shift ;;
	esac
	shift
done

if [ -z $outformat ]; then
	outformat='-c'
fi 

# check_binaries
printf "<verbatim>\nTesting if all binaries are available"
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK $SYS_SCP
if [ $? -gt 0 ]; then
	test_failed
else
	test_done
fi

printf "L&B server: '$remotehost'\n"
if [ "$remotehost" == "" ]; then
	printf "L&B server not specified, exittig...\n\n"
	exit 1
fi

if [ $COPYPROXY -eq 1 ]; then
	printf "Testing credentials... "
	timeleft=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^timeleft" | ${SYS_SED} "s/timeleft\s*:\s//" 2> /dev/null`

	if [ "$timeleft" = "" ]; then
	        printf "No credentials"
		COPYPROXY=0
        	test_skipped
	else
        	if [ "$timeleft" = "0:00:00" ]; then
	                printf "Credentials expired"
			COPYPROXY=0
                	test_skipped
        	else
                	test_done

			# Get path to the proxy cert
			printf "Getting proxy cert path... "

			PROXYCERT=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^path" | ${SYS_SED} "s/path\s*:\s//"`

		        if [ "$PROXYCERT" = "" ]; then
                		printf "Unable to identify the path to your proxy certificate"
				COPYPROXY=0
        		        test_skipped
		        else
				printf "$PROXYCERT"
        		        test_done

				scp $PROXYCERT root@$remotehost:/tmp/
			fi
		fi
	fi
fi

if [ "$PROXYCERT" == "" ]; then
	PROXYCERT="none"
fi

printf "Generating the 'arrange' script... "
gen_arrange_script $remotehost $COPYPROXY
test_done

TERMCOLS=`stty size | awk '{print $2}'`

chmod +x arrange_lb_test_root.sh

scp arrange_lb_test_root.sh root@$remotehost:/tmp/

ssh -l root $remotehost "sh /tmp/arrange_lb_test_root.sh "$PROXYCERT" glite $TERMCOLS $outformat"

		

