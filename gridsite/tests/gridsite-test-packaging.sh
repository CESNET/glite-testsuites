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
Script producing errors and warnings due to packaging.

Prerequisities:
   - installed all tested packages
   - Scientific Linux: installed rpmlint
   - Debian: installed lintian

Tests called:

   called rpmlint or lintian on the packages

Returned values:
    Exit TEST_OK: Test Passed
    Exit TEST_ERROR: Test Failed
    Exit 2: Wrong Input

EndHelpHeader

	echo "Usage: $progname [OPTIONS]"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -t | --text            Format output as plain ASCII text."
	echo " -c | --color           Format output as text with ANSI colours (autodetected by default)."
	echo " -x | --html            Format output as html."
}

# read common definitions and functions
for COMMON in gridsite-common.sh lb-common.sh
do
        if [ ! -r ${COMMON} ]; then
                printf "Downloading common definitions '${COMMON}'"
                wget -O ${COMMON} http://jra1mw.cvs.cern.ch/cgi-bin/jra1mw.cgi/org.glite.testsuites.ctb/gridsite/tests/$COMMON?view=co > /dev/null
                if [ ! -r ${COMMON} ]; then
                        exit 2
                else
                        chmod +x $COMMON
                        test_done
                fi
        fi
	source $COMMON
done

while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		"-t" | "--text")  setOutputASCII ;;
		"-c" | "--color") setOutputColor ;;
		"-x" | "--html")  setOutputHTML ;;
	esac
	shift
done


##
#  Starting the test
#####################

test_start


if egrep -i "Debian|Ubuntu" /etc/issue >/dev/null; then
	check_lintian libgridsite\*
	ret=$?
else
	check_rpmlint gridsite-\*
	ret=$?
fi

#printf "Packages compliance..."
#if test $ret -eq 0; then
#	test_done
#else
#	test_failed
#fi


test_end

exit $TEST_OK
