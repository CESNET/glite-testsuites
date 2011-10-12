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
Script for testing correct reporting of LB server properties over BDII/LDAP.
This should also be thought of as a regression test for ggus ticket #62737.

Prerequisities:
   - LB server
   - environment variables set:

     GLITE_WMS_QUERY_SERVER 

Tests called:

    ldap query to the server, checking the output

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
printf "Testing if all essential binaries are available"
check_binaries $SYS_GREP $SYS_SED $SYS_AWK $SYS_LDAPSEARCH
if [ $? -gt 0 ]; then
	test_failed
else
	test_done
fi

printf "Testing optional WS client binary"
check_binaries $LBWSGETVERSION
if [ $? -gt 0 ]; then
	printf " ... not present. Some tests will be skipped\n"
	WSBIN="no"
else
	test_done

	printf "Testing credentials"
	check_credentials
	if [ $? -gt 0 ]; then
		WSBIN="no"
	else
		WSBIN="yes"
	fi

fi

# Register job:

server=`${SYS_ECHO} ${GLITE_WMS_QUERY_SERVER} | ${SYS_SED} 's/:.*$//'`

printf "Checking if BDII operational... "
$SYS_LDAPSEARCH -x -H ldap://${server}:2170 -b 'o=infosys' > ldap.$$.out
if [ $? -gt 0 ]; then	
	test_failed
	print_error "No reply"
else
	test_done
fi

printf "Checking Glue 1 root entry... "
$SYS_LDAPSEARCH -x -H ldap://${server}:2170 -b 'o=grid' 'GlueServiceType=org.glite.lb.Server' > ldap.$$.out
if [ $? -gt 0 ]; then	
	test_failed
	print_error "No reply"
else
	test_done
fi

printf "Checking ServiceStatus (Regression into bug #76174)... "
health=`$SYS_GREP GlueServiceStatus: ldap.$$.out | $SYS_SED 's/^[^:]*: *//'`
if [ "$health" == "" ]; then
	print_error "GlueServiceStatus not specified"
	test_failed
else
	printf "$health"
	if [ "$health" == "OK" ]; then
		test_done
	else
		test_failed
	fi
fi

printf "Checking Glue 2.0 entry with 'o=glue'... "
$SYS_LDAPSEARCH -x -H ldap://${server}:2170 -b 'o=glue' -S GLUE2EntityCreationTime 'GLUE2EndpointInterfaceName=org.glite.lb.Server' > ldap.$$.out
if [ $? -gt 0 ]; then	
	test_failed
	print_error "No reply"
else
	test_done
fi

printf "Checking GLUE2 HealthStatus (Regression into bug #76173)... "
health=`$SYS_GREP GLUE2EndpointHealthState: ldap.$$.out | $SYS_TAIL -n 1 | $SYS_SED 's/^[^:]*: *//'`
if [ "$health" == "" ]; then
	print_error "GLUE2EndpointHealthState not specified"
	test_failed
else
	printf "$health"
	if [ "$health" == "ok" ]; then
		test_done
	else
		test_failed
	fi
fi

printf "Checking GlueServiceVersion (Regression into bug #55482)... "
glservver=`$SYS_GREP GLUE2EndpointImplementationVersion ldap.$$.out | $SYS_TAIL -n 1 | $SYS_SED 's/^.*GLUE2EndpointImplementationVersion:\s*//'`
if [ "$glservver" == "" ]; then	
	print_error "GLUE2EndpointImplementationVersion not specified"
	test_failed
else
	printf "$glservver"
	test_done

	printf "Reading version through WS... "
	if [ "$WSBIN" == "yes" ]; then
		servername=`echo ${GLITE_WMS_QUERY_SERVER} | ${SYS_SED} "s/:.*//"`
		wsglservver=`$LBWSGETVERSION -m ${servername}:${GLITE_LB_SERVER_WPORT} | $SYS_SED 's/^.*Server version:\s*//'`
		if [ "$wsglservver" == "" ]; then	
			test_failed
		else
			printf "$wsglservver"
			test_done

			printf "Comparing versions: '$glservver' == '$wsglservver'"
			if [ "$glservver" == "$wsglservver" ]; then
				test_done
			else
				test_failed
			fi
		fi
	else
		test_skipped
	fi
fi

rm ldap.$$.out

		

test_end
} &> $logfile

if [ $flag -ne 1 ]; then
 	cat $logfile
 	$SYS_RM $logfile
fi
exit $TEST_OK

