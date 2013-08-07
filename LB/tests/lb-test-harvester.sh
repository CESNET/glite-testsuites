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
Script for local testing of L&B harvester.

Prerequisities:
   - posgtgresql server running, with appropriate user access
   - mysql server running, with appropriate user access
   - environment variables set (may be specified in site-info.def):

  GLITE_LOCATION ................... gLite location
  GLITE_MYSQL_ROOT_PASSWORD ........ mysql root password
  GLITE_RTM_TEST_ADDITIONAL_ARGS ... L&B harvester additional arguments
                                     (--old required for L&B < 2.0)

  For full list of the possible environment variables, see '`which glite-lb-harvester.sh` --help'.

Tests called (glite-lb-harvester.sh script):

  basic:   notifications for basic events (submitted/waiting/running)
  rebind:  rebinding of the notifications
  cleanup: proper dropping of the notifications on quit
  refresh: renewing of the notifications
  JDL:     getting of the attributes from JDL

Returned values:
    Exit TEST_OK: Test Passed
    Exit TEST_ERROR: Test Failed
    Exit 2: Wrong Input

EndHelpHeader

	echo "Usage: $progname [OPTIONS] LB_SERVER_1 [LB_SERVER_2 ...] "
	echo "Options:"
	echo " -h | --help             Show this help message."
	echo " -o | --output 'file'    Redirect all output to the 'file' (stdout by default)."
	echo " -t | --text             Format output as plain ASCII text."
	echo " -c | --color            Format output as text with ANSI colours (autodetected by default)."
	echo " -x | --html             Format output as html."
	echo " -s | --site-info 'file' site-info.def file (mysql password, ...)."
	echo ""
}

# read common definitions and functions
COMMON=lb-common.sh
if [ ! -r ${COMMON} ]; then
	printf "Common definitions '${COMMON}' missing!"
	exit 2
fi
source ${COMMON}

export GLITE_LOCATION GLITE_MYSQL_ROOT_PASSWORD GLITE_RTM_TEST_ADDITIONAL_ARGS


while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		"-t" | "--text")  setOutputASCII ;;
		"-c" | "--color") setOutputColor ;;
		"-x" | "--html")  setOutputHTML ;;
		"-s" | "--site")
			shift
			cat "$1" | grep -v '^#' | grep -v '^[ \t]*$' | sed 's/^/export /' > site-info.def.tmp.$$
			source "site-info.def.tmp.$$"
			rm -f "site-info.def.tmp.$$"
			site=1
			if test -z "$GLITE_MYSQL_ROOT_PASSWORD"; then
				export GLITE_MYSQL_ROOT_PASSWORD="$MYSQL_PASSWORD"
			fi
			;;
		*) showHelp && exit 2 ;;
	esac
	shift
done

DEBUG=2

##
#  Starting the test
#####################

{
test_start


##
# ==== Various sanity checks first ====
##

# check_binaries
# (harvester test script is using own names of the all binaries)
printf "Testing if all binaries are available"
check_binaries $SYS_GREP $SYS_SED $SYS_CAT $SYS_TAIL $SYS_DATE $GRIDPROXYINFO $LBJOBREG $LBLOGEV $LBPURGE mysqladmin mysql createdb dropdb psql
if [ $? = 0 ]; then
	test_done
else
	test_failed
	print_error "Some binaries missing!"
	test_end
	exit 2
fi

# skip the whole test if PostreSQL support has not been compiled in
# (for heimdal flavour on Debian)
printf "Checking if PostgreSQL supported"
if ls /usr/lib*/libglite_lbu_db.so.*.* >/dev/null; then
	if ! ldd /usr/lib*/libglite_lbu_db.so.*.* | grep -q libpq; then
		test_done
		print_info "PosgreSQL not supported by glite-lbjp-common-db"
		exit 2
	fi
fi
test_done

printf "Testing credentials"
check_credentials_and_generate_proxy
if [ $? != 0 ]; then
	test_end
	exit 2
fi

printf "Testing access to MySQL"
if [ -z "$GLITE_LB_TEST_DB" ]; then
	MYSQL_ARGS="-u ${GLITE_MYSQL_ROOT_USER:-root}"
	[ -z "$GLITE_MYSQL_ROOT_PASSWORD" ] || MYSQL_ARGS="--password=${GLITE_MYSQL_ROOT_PASSWORD} $MYSQL_ARGS"
	mysqladmin $MYSQL_ARGS status >/dev/null
	if [ $? = 0 ]; then
		test_done
	else
		test_failed
		print_error "MySQL not running or access denied!"
		if [ -z "$GLITE_MYSQL_ROOT_PASSWORD" ]; then
			print_warning "\$GLITE_MYSQL_ROOT_PASSWORD not specified"
		fi
		if [ -z "$site" ]; then
			print_warning "site-info.def file not specified"
		fi
		test_end
		exit 2
	fi
else
	printf " ... using $GLITE_LB_TEST_DB, not tested"
	test_skipped
fi

printf "Testing access to PostgreSQL"
if [ -z "$GLITE_RTM_TEST_DB" ]; then
	PG_ARGS="-U ${GLITE_PG_ROOT_USER:-postgres}"
	echo "SHOW server_version;" | psql -At $PG_ARGS >/dev/null
	if [ $? = 0 ]; then
		test_done
	else
		test_failed
		print_error "PosgreSQL not running or access denied!"
		exit 2
	fi
else
	printf " ... using $GLITE_RTM_TEST_DB, not tested"
	test_skipped
fi

printf "L&B harvester test script in PATH"
if which glite-lb-harvester-test.sh >/dev/null 2>&1; then
	test_done
else
	test_failed
	print_error "glite-lb-harvester-test.sh not found"
	exit 2
fi

##
# ==== L&B harvester test ====
##

printf "Launching the L&B harvester test..."
print_newline
if [ -n "$is_html" ]; then
	local_amp='&amp;'
	printf "<pre>"
else
	local_amp='&'
fi
glite-lb-harvester-test.sh stop
(glite-lb-harvester-test.sh 2>&1; echo $? > res.$$.txt) | sed "s,&,$local_amp,"
err=`cat res.$$.txt`; rm -f res.$$.txt
if [ -n "$is_html" ]; then
	printf "</pre>"
fi

if [ "$err" = "0" ]; then
	test_done
else
	test_failed
	print_error "L&B harvester test failed!"
	test_end
	exit 1
fi

test_end
}

exit $TEST_OK
