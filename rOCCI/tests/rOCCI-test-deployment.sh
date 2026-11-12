#!/bin/bash
#The work represented by this source file is partially or entirely funded
#by the EGI-InSPIRE project through the European Commission's 7th Framework
#Programme (contract # INFSO-RI-261323)
#
#Copyright (c) 2014 CESNET
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#http://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.

# show help and usage
progname=`basename $0`
showHelp()
{
cat << EndHelpHeader
Script for basic testing of rOCCI deployment by listing categories.

Prerequisities:
   - rOCCI CLI installed
   - the server answering on \$ROCCI_SERVER:\$ROCCI_PORT (11443 by default)
   - credentials of the backend currently selected in $ROCCI_INFO, which the
     backend switch writes: run.sh switches before calling this, or by hand
     'sudo -n $ROCCI_TOGGLE dummy'

Tests called:

    deployment presence, and that what it answers is a list of categories

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
COMMON=`dirname $0`/rOCCI-common.sh
if [ ! -r ${COMMON} ]; then
	printf "Common definitions '${COMMON}' missing!\n"
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
TEST_RESULT=$TEST_OK

##
#  Starting the test
#####################

{
test_start


# check_binaries
printf "Testing if all binaries are available"
check_binaries $OCCI_CLIENT $SYS_CURL
if [ $? -gt 0 ]; then
	test_failed
	print_error "the rOCCI command line client and curl are what this test is made of (docs/requirements.md)"
	TEST_RESULT=$TEST_ERROR
else
	test_done
fi


# curl args
curl_args="--silent -i"
capath=''
for dir in '/etc/grid-security/certificates'; do
	if [ -d ${dir} ]; then
		if [ -z "${capath}" ]; then
			capath="${dir}"
		else
			capath="${capath}:${dir}"
		fi
	fi
done
if [ -n "${capath}" ]; then
	curl_args="${curl_args} --capath ${capath}"
fi


printf "Checking credentials"
if [ -r ${ROCCI_INFO} ]; then
	source ${ROCCI_INFO}
fi
if [ -n "${rocci_password}" ]; then
	test_done
	can_continue=1
else
	test_failed
	print_error "no credentials for the current backend in ${ROCCI_INFO} - switch one first: sudo -n ${ROCCI_TOGGLE} dummy"
	TEST_RESULT=$TEST_ERROR
	can_continue=0
fi


# Everything below is one request and what came back in it. Without credentials, or
# once the request failed, there is nothing left to look at - but the checks are still
# reported, as skipped rather than silently absent.
printf "Listing categories"
if [ "$can_continue" -eq 0 ]; then
	test_skipped
	print_error "nothing to ask the server for"
else
	# The reply and just its body, in two files: the status line comes out of the first
	# and the category checks are made on the second, so that a header line cannot
	# satisfy them. In $STATE_DIR rather than under a fixed name in /tmp, where a
	# second run would overwrite the first and anybody could have created it before.
	file_out=`mktemp "${STATE_DIR:-/tmp}/rocci-categories.XXXXXX"`
	credfile=`mktemp "${STATE_DIR:-/tmp}/rocci-credentials.XXXXXX"`
	if [ -z "$file_out" ] || [ -z "$credfile" ]; then
		test_failed
		print_error "cannot write into ${STATE_DIR:-/tmp} - the reply has to be kept somewhere"
		TEST_RESULT=$TEST_ERROR
		can_continue=0
	else
		file_cat="$file_out.body"
		chmod 600 $credfile
		# The password reaches curl from a file, not from its command line: as an
		# argument it would sit in the process list, readable by everybody on this
		# machine for as long as the request takes.
		#
		# curl's --config rather than --netrc-file, because a netrc line is a sequence of
		# whitespace-separated tokens and cannot carry a password with a space in it - the
		# request then goes out with the password cut short at the space and comes back 401
		# however right the credentials were. A config value can be quoted, so it is, and a
		# backslash or a quote inside the quotes has to be doubled to stay itself.
		printf 'user = "%s"\n' \
			"$(printf '%s' "$rocci_user:$rocci_password" | sed -e 's/[\\"]/\\&/g')" > $credfile
		trap '$SYS_RM $file_out $file_cat $credfile' EXIT INT TERM

		${SYS_CURL} ${curl_args} --config "$credfile" -H 'Accept: text/plain' \
			${ROCCI_URL}/-/ > ${file_out}
		ret=$?

		sed -i ${file_out} -e 's/\r//g'
		awk '{if (ok) {print $0}} /^$/ {ok=1}' ${file_out} > ${file_cat}
		http_code=`grep '^HTTP' ${file_out} | head -n 1 | sed -e 's,^HTTP/[^ ]\+\s\+\([0-9]\+\).*,\1,'`

		if [ ${ret} -eq 0 -a x"${http_code}" = x"200" ]; then
			test_done
		else
			if [ ${ret} -eq 0 ]; then
				printf "... HTTP code ${http_code}"
			else
				printf "... curl exit code ${ret}"
			fi
			test_failed
			echo "${SYS_CURL} ${curl_args} --config <credentials> -H 'Accept: text/plain' ${ROCCI_URL}/-/"
			cat ${file_out}
			printf "${lf}"
			TEST_RESULT=$TEST_ERROR
			can_continue=0
		fi
	fi
fi


printf "Checking body contains any categories"
if [ "$can_continue" -eq 0 ]; then
	test_skipped
else
	grep -q '^Category:.*;scheme=".*"' ${file_cat}
	if [ $? -eq 0 ]; then
		test_done
	else
		test_failed
		print_error "the answer carried no category - the reply is printed above"
		TEST_RESULT=$TEST_ERROR
	fi
fi


printf "Checking body contains only categories"
if [ "$can_continue" -eq 0 ]; then
	test_skipped
else
	grep -vq '^Category:.*;scheme=".*"' ${file_cat}
	if [ $? -ne 0 ]; then
		test_done
	else
		test_failed
		print_error "the answer was not only a list of categories - the reply is printed above"
		TEST_RESULT=$TEST_ERROR
	fi
fi

test_end
} &> $logfile

if [ $flag -ne 1 ]; then
	cat $logfile
	$SYS_RM $logfile
fi

exit $TEST_RESULT
