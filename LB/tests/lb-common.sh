# $Header$
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
# ------------------------------------------------------------------------------
# Definitions of functions and variables common to LB test scripts
#
# What is here is only what is specific to the Logging & Booking service: where
# its installation and binaries are, the LB service ports and sockets, and the
# three helpers that talk the LB protocol (try_purge, check_srv_version,
# notif_wait).
#
# Everything generic - the output modes and the test_* verbs, the SYS_* binary
# names, ping_host(), check_binaries(), check_socket(), check_listener(), the
# build-log checker and the credential helpers - lives in tools/lib/
# and arrives through testenv.sh, sourced below.
#
# ------------------------------------------------------------------------------

# read common definitions and functions - walking up from this file, so that
# neither the current directory nor the way the test was invoked matters
TEST_COMMON_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIBROOT=$TEST_COMMON_DIR
while [ ! -r "$LIBROOT/tools/lib/testenv.sh" ] && [ "$LIBROOT" != "/" ]; do
	LIBROOT=$(dirname -- "$LIBROOT")
done
if [ ! -r "$LIBROOT/tools/lib/testenv.sh" ]; then
	printf "Common definitions 'tools/lib/testenv.sh' not found above '${TEST_COMMON_DIR}'!\n"
	exit 2
fi
source "$LIBROOT/tools/lib/testenv.sh"

ulimit -c unlimited

# define variables
GLITE_LB_LOCATION=${GLITE_LB_LOCATION:-$GLITE_LOCATION}
GLITE_LOCATION=${GLITE_LOCATION:-'/usr'}
for dir in $GLITE_LOCATION $GLITE_LOCATION/lib64/glite-lb $GLITE_LOCATION/lib/glite-lb; do
	if test -d "$dir/examples"; then PATH="$dir/examples:$PATH"; fi
done
PATH="$GLITE_LOCATION/bin:$PATH"
export PATH

# LB binaries
LBLOGEVENT=glite-lb-logevent
LBJOBLOG=glite-lb-job_log
LBWSJOBLOG=glite-lb-ws_joblog
LBJOBREG=glite-lb-job_reg
LBUSERJOBS=glite-lb-user_jobs
LBJOBSTATUS=glite-lb-job_status
LBTHRJOBSTATUS=glite-lb-job_status_threaded
LBWSJOBSTATUS=glite-lb-ws_jobstat
LBWSGETVERSION=glite-lb-ws_getversion
LBPURGE=glite-lb-purge
LBCHANGEACL=glite-lb-change_acl
LBMON=glite-lb-lbmon
LBNOTIFY=glite-lb-notify
LBPURGE=glite-lb-purge
LBPARSEEFILE=glite-lb-parse_eventsfile
LB4AGUACTINFO=glite-lb-ws_lb4agu_GetActivityInfo
LB4AGUACTSTATUS=glite-lb-ws_lb4agu_GetActivityStatus
LBREGSANDBOX=glite-lb-register_sandbox
LBHISTORY=glite-lb-state_history
LBCMSCLIENT=glite-lb-cmsclient
LBQUERYEXT=glite-lb-query_ext
LBNOTIFKEEPER=glite-lb-notif-keeper
LBDUMP=glite-lb-dump
LBLOAD=glite-lb-load

LB_LOGD=glite-lb-logd
LB_INTERLOGD=glite-lb-interlogd
LB_SERVER=glite-lb-bkserverd

LB_READY_SH=glite-lb-ready.sh
LB_RUNNING_SH=glite-lb-running.sh
LB_DONE_SH=glite-lb-done.sh
LB_CLEARED_SH=glite-lb-cleared.sh

LB_STATS=glite-lb-stats
LB_FROMTO=glite-lb-stats-duration-fromto

# default LB ports
GLITE_LB_SERVER_PORT=${GLITE_LB_SERVER_PORT:-9000}
GLITE_LB_IL_SOCK=${GLITE_LB_IL_SOCK:-/tmp/interlogger.sock}
let GLITE_LB_SERVER_QPORT=${GLITE_LB_SERVER_PORT}+1
if [ -z "${GLITE_LB_SERVER_WPORT}" ]; then 
	let GLITE_LB_SERVER_WPORT=${GLITE_LB_SERVER_PORT}+3
fi

GLITE_LB_LOGGER_PORT=${GLITE_LB_LOGGER_PORT:-9002}

# default sockets
GLITE_WMS_LBPROXY_STORE_SOCK=${GLITE_WMS_LBPROXY_STORE_SOCK:-/tmp/lb_proxy_}

function try_purge()
{
                        #Purge test job
                        joblist=$1

                        printf "Purging test job (Trying the best, result will not be tested)\n"

                        ${LBPURGE} -j ${joblist}

                        $SYS_RM ${joblist}
	
}

function check_srv_version()
{
        check_binaries $LBWSGETVERSION
        if [ $? -gt 0 ]; then
		return 2
        else
		servername=`echo ${GLITE_WMS_QUERY_SERVER} | ${SYS_SED} "s/:.*//"`
                wsglservver=`$LBWSGETVERSION -m ${servername}:${GLITE_LB_SERVER_WPORT} | $SYS_SED 's/^.*Server version:\s*//'`
                if [ "$wsglservver" = "" ]; then
               		return 2
                else
	
			SRVVER=`$SYS_ECHO $wsglservver | $SYS_GREP -o -E "^[0-9]+\.[0-9]+"`
			CHKVER=`$SYS_ECHO $2 | $SYS_GREP -o -E "^[0-9]*\.[0-9*]"`

			printf "Srv. version $SRVVER $1 $CHKVER? "
		        cresult=`$SYS_EXPR $SRVVER $1 $CHKVER`
	                if [ "$cresult" -eq "1" ]; then
				printf "yes "
				return 0
                	else
				printf "no "
				return 1
        	        fi
		fi
	fi
	return 0
}

function notif_wait() {
	timeout="$1"
	jobid="$2"
	f="$3"

	while ! $SYS_GREP ${jobid} "$f" > /dev/null 2>&1; do
		sleep 1
		printf "."
		timeout=$((timeout-1))
		if [ $timeout -le 0 ]; then
			printf "timeout"
			break;
		fi
	done
	sleep 1
	echo
	$SYS_GREP ${jobid} $$_notifications.txt > /dev/null
}
