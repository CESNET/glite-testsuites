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
	check_packaging_help $progname
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
	check_lintian glite-px-\* libglite-security-proxyrenewal-\* emi-px-\*
	ret=$?
else
	check_rpmlint glite-px-\* emi-px\*
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
