# $Header$
# ------------------------------------------------------------------------------
# Definitions of functions and variables common to LB test scripts
#
#   ping_host() - basic network ping
#   check_binaries() - check for binary executables, calls check_exec()
#   check_socket() - TCPecho to host:port
#
# ------------------------------------------------------------------------------

# read common definitions and functions
TEST_COMMON=test-common.sh
if [ ! -r ${TEST_COMMON} ]; then
	printf "Common definitions '${TEST_COMMON}' not found!\n"
	exit 2	
fi
. ${TEST_COMMON}

# define variables
GLITE_LOCATION=${GLITE_LOCATION:-/opt/glite}
PATH=$GLITE_LOCATION/bin:$GLITE_LOCATION/examples:$PATH
export PATH

LBLOGEVENT=glite-lb-logevent
LBJOBLOG=glite-lb-job_log
LBJOBREG=glite-lb-job_reg
LBUSERJOBS=glite-lb-user_jobs
LBJOBSTATUS=glite-lb-job_status
LBPURGE=glite-lb-purge
LBCHANGEACL=glite-lb-change_acl
LBMON=glite-lb-lbmon

LB_LOGD=glite-lb-logd 
LB_INTERLOGD=glite-lb-interlogd
LB_SERVER=glite-lb-bkserverd

GLITE_LB_SERVER_PORT=${GLITE_LB_SERVER_PORT:-9000}
let GLITE_LB_SERVER_QPORT=${GLITE_LB_SERVER_PORT}+1
if [ -z "${GLITE_LB_SERVER_WPORT}" ]; then 
	let GLITE_LB_SERVER_WPORT=${GLITE_LB_SERVER_PORT}+3
fi

TEST_SOCKET=$SAME_SENSOR_HOME/tests/testSocket

DEBUG=2

# ping host
function ping_host()
{
	if [ -z $1 ]; then
		print_newline
		print_error "No host to ping"
		return $TEST_ERROR
	fi
	PING_HOST=$1
	# XXX: there might be a better way to test the network reachability
	result=`ping -c 3 $PING_HOST 2>/dev/null | grep " 0% packet loss"| wc -l`
	if [ $result -gt 0 ]; then
		return $TEST_OK
	else 
		return $TEST_ERROR
	fi
}


# check the binaries
function check_exec()
{
	if [ -z $1 ]; then
		print_newline
		print_error "No binary to check"
		return $TEST_ERROR
	fi
	# XXX: maybe use bash's command type?
	local ret=`which $1`
	if [ $? -eq 0 ] && [ -x $ret ]; then 
		return $TEST_OK
	else
		return $TEST_ERROR
	fi
}

function check_binaries()
{
	local err=0
	for file in $LBLOGEVENT $LBJOBLOG $LBJOBREG $LBUSERJOBS $LBJOBSTATUS $LBCHANGEACL
	do	
		printf "  checking binary %s" "$file"
		check_exec $file 
		if [ $? -eq 0 ]; then
			test_done
		else
			test_failed
			print_error "file $file not found"
			err=1
		fi
	done
	if [ $err -eq 0 ];  then 
		return $TEST_OK
	else
		return $TEST_ERROR
	fi
}

# check socket
function check_socket()
{
	if [ $# -lt 2 ]; then
		print_newline
		print_error "No host:port to check"
		return $TEST_ERROR
	fi
	$TEST_SOCKET $1 $2
	if [ $? -eq 0 ];  then 
		return $TEST_OK
	else
		return $TEST_ERROR
	fi
}
