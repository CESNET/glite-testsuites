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
for COMMON in px-common.sh ../../LB/tests/lb-common.sh
do
	if [ ! -r ${COMMON} ]; then
		printf "Common definitions '${COMMON}' missing!"
		exit 2
	fi
	source ${COMMON}
done
[ -f lb-generate-fake-proxy.sh ] || ln -s ../../LB/tests/lb-generate-fake-proxy.sh .

WRKDIR=`pwd`

logfile=$$.tmp
flag=0
NL="\n"
while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		"-o" | "--output") shift ; logfile=$1 flag=1 ;;
		"-t" | "--text")  setOutputASCII ;;
		"-c" | "--color") setOutputColor ;;
		"-x" | "--html")  setOutputHTML; NL="<br>" ;;
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
check_credentials_and_generate_proxy 1
if [ $? != 0 ]; then
        test_end
        exit 2
fi

if [ "$x509_USER_CERT" = "" -o "$x509_USER_KEY" = "" ]; then
	source ./lb-generate-fake-proxy.sh --hours 1
fi
cd $WRKDIR

printf "User Cert $x509_USER_CERT$NL"
printf "User Key $x509_USER_KEY$NL"
chmod 600 $x509_USER_CERT $x509_USER_KEY

JOBID=https://fake.job.id/xxx

ORIG_PROXY=`voms-proxy-info | grep -E "^path" | sed 's/^path\s*:\s*//'`
PROXYDN=`voms-proxy-info | grep -E "^identity" | sed 's/^identity\s*:\s*//'`
#myproxy-store --certfile $ORIG_PROXY --keyfile $ORIG_PROXY -s localhost -d
printf "Registering proxy by calling myproxy-init -s localhost -d -n -t 1 -c 1 --certfile $x509_USER_CERT --keyfile $x509_USER_KEY$NL" 
#myproxy-init -s localhost -d -n -t 1 -c 1 --certfile $x509_USER_CERT --keyfile $x509_USER_KEY
myproxy-init -s localhost -d -n --certfile $x509_USER_CERT --keyfile $x509_USER_KEY
#myproxy-info -s localhost -l "$PROXYDN"

printf "Getting registered proxy... "
REGISTERED_PROXY=`glite-proxy-renew -s localhost -f $ORIG_PROXY -j $JOBID start`

if [ "$REGISTERED_PROXY" = "" ]; then
	test_failed
	print_error "Could not set renewal"
	exit 1
fi
test_done

printf "\tProxy:\t$ORIG_PROXY$NL\tRenew:\t$REGISTERED_PROXY$NL"; 


printf "Checking key lengths...$NL"
ORIGLENGTH=`voms-proxy-info -file $ORIG_PROXY | grep strength | grep -E -o "[0-9]+"`
REGISTEREDLENGTH=`voms-proxy-info -file $REGISTERED_PROXY | grep strength | grep -E -o "[0-9]+"`

printf "Original proxy key: $ORIGLENGTH bits "
if [ "$ORIGLENGTH" -lt "1024" ]; then
	test_failed
else
	test_done
fi
printf "Registered proxy key: $REGISTEREDLENGTH bits "
if [ "$REGISTEREDLENGTH" -lt "1024" ]; then
	test_failed
else
	test_done
fi

printf "Checking time left on registered proxy... "
REGISTEREDTIMELEFT=`voms-proxy-info -file $REGISTERED_PROXY | grep timeleft | grep -E -o "[0-9]+:[0-9]+:[0-9]+"`
#Use this for conversion: date --utc --date "1970-1-1 0:0:0" +%s
REGISTEREDTIMELEFTSEC=`date --utc --date "1970-1-1 $REGISTEREDTIMELEFT" +%s`
printf "($REGISTEREDTIMELEFT, i.e. $REGISTEREDTIMELEFTSEC s)"
if [ ! $REGISTEREDTIMELEFTSEC -gt 0 ]; then
	test_failed
	print_error "Failed to retrieve time left"
	exit 1
fi
test_done

printf "sleeping 1800 (Sorry, no other way to let the proxy age enough)... "; 
sleep 1805;
test_done


printf "Checking time left on registered proxy... "
REGISTEREDTIMELEFT=`voms-proxy-info -file $REGISTERED_PROXY | grep timeleft | grep -E -o "[0-9]+:[0-9]+:[0-9]+"`
REGISTEREDTIMELEFTSEC=`date --utc --date "1970-1-1 $REGISTEREDTIMELEFT" +%s`
printf "($REGISTEREDTIMELEFT, i.e. $REGISTEREDTIMELEFTSEC s)"
if [ ! $REGISTEREDTIMELEFTSEC -gt 0 ]; then
	test_failed
	print_error "Failed to retrieve time left"
	exit 1
fi
test_done

printf "Checking time left on original proxy... "
ORIGINALTIMELEFT=`voms-proxy-info -file $ORIG_PROXY | grep timeleft | grep -E -o "[0-9]+:[0-9]+:[0-9]+"`
ORIGINALTIMELEFTSEC=`date --utc --date "1970-1-1 $ORIGINALTIMELEFT" +%s`
printf "($ORIGINALTIMELEFT, i.e. $ORIGINALTIMELEFTSEC s)"
if [ ! $ORIGINALTIMELEFTSEC -gt 0 ]; then
	test_failed
	print_error "Failed to retrieve time left"
	exit 1
fi
test_done

printf "Checking renewal ($REGISTEREDTIMELEFTSEC > $ORIGINALTIMELEFTSEC)? "
expr $REGISTEREDTIMELEFTSEC \> $ORIGINALTIMELEFTSEC > /dev/null
if [ $? -eq 0 ]; then
	test_done
else
	test_failed
	print_error "Proxy was not renewed"
fi

printf "Other particulars:$NL"
printf "Registered proxy `voms-proxy-info -file $REGISTERED_PROXY -fqan -actimeleft`$NL" 
printf "Original proxy `voms-proxy-info -file $ORIG_PROXY -fqan -actimeleft`$NL"
printf "Registered proxy `voms-proxy-info -file $REGISTERED_PROXY -identity`$NL" 
printf "Original proxy `voms-proxy-info -file $ORIG_PROXY -identity`$NL" 

printf "Checking if test uses fake proxy... "
voms-proxy-info | grep -E "^subject.*.L=Tropic.O=Utopia.OU=Relaxation" > /dev/null
if [ $? -eq 0 ]; then
	printf "yes."
	test_done
	printf "Generating new proxy... "
	cd "$WRKDIR"
	./lb-generate-fake-proxy.sh
	if [ $? -eq 0 ]; then
		test_done
		printf "Registering new proxy for renewal (regression into Savannah Bug #90610)... "
		NEW_REGISTERED=`glite-proxy-renew -s localhost -f $ORIG_PROXY -j $JOBID start`
		if [ "$NEW_REGISTERED" == "$REGISTERED_PROXY" ]; then
			test_done
			printf "Checking time left on new proxy... "
			NEWTIMELEFT=`voms-proxy-info -file $REGISTERED_PROXY | grep timeleft | grep -E -o "[0-9]+:[0-9]+:[0-9]+"`
			NEWTIMELEFTSEC=`date --utc --date "1970-1-1 $NEWTIMELEFT" +%s`
			printf "$NEWTIMELEFT ($NEWTIMELEFTSEC)"
			test_done
			printf "Checking if old proxy ($REGISTEREDTIMELEFTSEC) was replaced by new ($NEWTIMELEFTSEC)... "
			expr $NEWTIMELEFTSEC \> $REGISTEREDTIMELEFTSEC > /dev/null
			if [ $? -eq 0 ]; then
				test_done
			else
			test_failed
				print_error "Proxy was not replaced"
			fi

			printf "Checking key length for the new proxy... "
			NEWLENGTH=`voms-proxy-info -file $NEW_REGISTERED | grep strength | grep -E -o "[0-9]+"`
			printf "New proxy key: $NEWLENGTH bits "
			if [ "$NEWLENGTH" -lt "1024" ]; then
			        test_failed
			else
			        test_done
			fi
		else
			test_failed
			print_error "Not created as the same registration!${NL}Old proxy: $REGISTERED_PROXY${NL}New proxy: $NEW_REGISTERED"
		fi
		printf "Removing 2nd registration... "
		glite-proxy-renew -j $JOBID stop;
		if [ $? -eq 0 ]; then
			test_done
		else
			test_failed
			print_error "Failed to stop"
		fi

	else
		test_failed
		print_error "Failed to generate proxy"
	fi


else
	printf "no."
	test_skipped
fi


printf "Stopping renewal... "
glite-proxy-renew -j $JOBID stop;
if [ $? -eq 0 ]; then
        test_done
else
	test_failed
	print_error "Failed to stop"
fi


printf "Checking if registered proxy was removed... "
if [ -f $REGISTERED_PROXY ]; then
	test_failed
	print_error "Registered proxy still exists ($REGISTERED_PROXY)"
else
	test_done
fi

UTOPIA=`voms-proxy-info -all | grep -A 100 "extension information" | grep "^issuer" | grep "L=Tropic" | grep "O=Utopia" | grep "OU=Relaxation"`
if [ "$UTOPIA" != "" ]; then
        printf "Possibly fake VOMS extensions. Regenerating... "
        voms-proxy-init -voms vo.org -key $x509_USER_KEY -cert $x509_USER_CERT | sed "s/\$/$NL/"
fi


printf "Checking VOMS attributes size to decide if it's possible to determine the status of bug #92806 (regression into bug #92806)... "
attrsize=`voms-proxy-info -all | grep ^attribute | sed -r 's/attribute\s*:\s*//' | wc -c`
if [ "$attrsize" == "" ]; then
	attrsize=0
fi
if [ $attrsize -gt 1024 ]; then
	printf "Registering proxy for renewal"
	ORIG_PROXY=`voms-proxy-info | grep -E "^path" | sed 's/^path\s*:\s*//'`
	REGISTERED=`glite-proxy-renew -s localhost -f $ORIG_PROXY -j $JOBID start`

	if [ "$REGISTERED" = "" ]; then
		printf "failed to renew with $attrsize bytes of attributes"
		test_failed
		print_error "Could not set renewal"
	else 
		printf "renewed with $attrsize bytes of attributes"
		test_done

		printf "Stopping renewal... "
		glite-proxy-renew -j $JOBID stop;
		if [ $? -eq 0 ]; then
			test_done
		else
			test_failed
			print_error "Failed to stop"
		fi
		
	fi
else
	printf "only $attrsize bytes of attributes"
	test_skipped
fi



test_end
} 

exit $TEST_OK

