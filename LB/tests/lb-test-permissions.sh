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
Script for testing permission settings on L&B files

Prerequisities:
   - L&B installed, configured and running

     GLITE_LOCATION

Tests called:

    checking file permissions

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

test_perms()
{
FAIL=0
for line in `$SYS_CAT $4`;do
	if [ -e $line ]; then
		$SYS_STAT -c=%A%U%G $line | $SYS_GREP -E "^=$1$2$3" > /dev/null
		if [ $? -gt 0 ]; then
			print_error "Incorrect permissions for $line"
			$SYS_LS -l $line
			FAIL=2
		fi
	else
		printf "File $line does not exist"
		if [ $FAIL = 0 ]; then
			FAIL=1
		fi
	fi
done

if [ $FAIL = 2 ]; then
	test_failed
else
	if [ $FAIL = 1 ]; then
		test_skipped
	else
		test_done
	fi
fi
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

DEBUG=2

##
#  Starting the test
#####################

{
test_start


# check_binaries
printf "Testing if all binaries are available"
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_CAT $SYS_STAT $SYS_LS
if [ $? -gt 0 ]; then
	test_failed
else
	test_done
fi

#lrwxrwxrwx 1 root root 29 Aug  2 10:31 /etc/glite-lb-dbsetup.sql -> glite-lb/glite-lb-dbsetup.sql
#lrwxrwxrwx 1 root root 37 Aug  2 10:31 /etc/glite-lb-index.conf.template -> glite-lb/glite-lb-index.conf.template
#-r--r--r-- 1 root root 990 May 10 07:50 /etc/glite-lb/harvester-test-dbsetup.sql

$SYS_CAT << EOF > 400glite
/home/glite/.certs/hostkey.pem
EOF

$SYS_CAT << EOF > 644glite
/var/log/glite/glite-lb-lcas.log
/var/log/glite/glite-lb-purger.log
/home/glite/.bashrc
/home/glite/.certs/hostcert.pem
/home/glite/.bash_profile
/home/glite/.bash_logout
EOF

$SYS_CAT << EOF > 644root
/etc/glite-lb/msg.conf
/usr/interface/lb-job-attrs2.xsd
/etc/glite-lb/log4crc
/etc/glite-lb/glite-lb-index.conf.template
/etc/glite-lb/glite-lb-harvester.conf
/etc/glite-lb/msg.conf.example
/etc/glite-lb/glite-lb-dbsetup.sql
/usr/interface/lb-job-record.xsd
/etc/glite-lb/lcas.db
/usr/interface/lb-job-attrs.xsd
/etc/glite-lb/glite-lb-authz.conf
/etc/gLiteservices
/etc/logrotate.d/lb-lcas
/etc/logrotate.d/lb-purger
EOF

$SYS_CAT << EOF > 664glite
/var/glite/glite-lb-bkserverd.pid
/var/glite/glite-lb-interlogd.pid
/var/glite/glite-lb-logd.pid
/var/glite/glite-lb-notif-interlogd.pid
/var/glite/glite-lb-proxy-interlogd.pid
EOF

$SYS_CAT << EOF > 755root
/etc/glite-lb/glite-lb-migrate_db2version20
/usr/share/glite-lb/msg-brokers-openwire
EOF

$SYS_CAT << EOF > s700glite
/tmp/lb_proxy_serve.sock
/tmp/lb_proxy_store.sock
/tmp/glite-lb-notif.sock
/tmp/glite-lbproxy-ilog.sock
/tmp/interlogger.sock
EOF

printf "Checking permissions and ownership for\n  Host key... "
test_perms "-r..------" glite glite 400glite

printf "  glite's home dir files... "
test_perms ".rw.r-.r-." glite glite 644glite

printf "  Config files..."
test_perms ".rw.r-.r-." root root 644root

printf "  PIDs..."
test_perms "-rw.rw.r-." glite glite 664glite

printf "  Admin scripts..."
test_perms "-rwxr-xr-x" root root 755root

printf "  Sockets... "
test_perms "srw.------" glite glite s700glite


$SYS_RM 400glite 644glite 644root 664glite 755root s700glite

test_end
} 

exit $TEST_OK

