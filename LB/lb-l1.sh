#!/bin/bash
##########################################################################################
# Script for testing of LB services 
# Basic test: PING
#             check LB binaries
#             check running services with sockets
#####################################################################################
#                                                              #
# Returned values:                                             #
#                                                              #
#                 Exit  TEST_OK: Test Passed                   #
#                 Exit  TEST_ERROR: Test Failed                #
#                 Exit  2: Wrong Input                         #
#                                                              #
# Authors: Shkelzen Rugovac, Frederic Munster, Othmane Bouhali #
################################################################
                                                                                
##
# defining variables
########################"
PATH=/opt/glite/examples:$PATH
#echo $PATH
LBLOGEV=${LBLOGEV:-glite-lb-logevent}
LBJOBLOG=${LBJOBLOG:-glite-lb-job_log}
LBJOBREG=${LBJOBREG:-glite-lb-job_reg}
LBUSERJOBS=${LBUSERJOBS:-glite-lb-user_jobs}
LBJOBSTAT=${LBJOBSTAT:-glite-lb-job_status}
LBPURGE=${LBPURGE:-glite-lb-purge}
LBCHANGEACL=${LBCHANGEACL:-glite-lb-change_acl}
LBMON=${LBMON:-glite-lb-lbmon}
LB_INTERLOGD=glite-lb-interlogd
LB_LOGD=glite-lb-logd 
DEBUG=2
##
# show help and usage
######################"
showHelp()
{
	echo  "Usage: $0 [OPTIONS] "
	echo  "Options:"
	echo  " -h | --help                   Show this help message."
        echo  " -m | --m lb_host              hostName or IPV4 adress "
	echo  " -g | --log 'logfile'          Redirect all output to the 'logfile'."
	echo  ""
#	echo  "For proper operation check your grid-proxy-info"
#	grid-proxy-info
}
if [ -z "$1" ]; then
  showHelp
  exit 2
fi
logfile=output.log
flag=0
while test -n "$1"
do
	case "$1" in
	"-h" | "--help") showHelp && exit 2 ;;
	"-m" | "--bkserver") shift ; LB_HOST=$1 ;;
	"-g" | "--log") shift ; logfile=$1 flag=1 ;;

	*) echo "Unrecognized option $1 try -h for help"; exit 2 ;;

	esac
	shift
done


##
# Ping the LB_HOST
######################

function ping_host
{
  echo  " Testing ping to $LB_HOST" >> $logfile
         result=`ping -c 5 $LB_HOST 2>/dev/null |  grep "0% packet loss"| wc -l`
  if [ $result -gt 0 ]; then
 	echo "Pinging $LB_HOST                        OK " >> $logfile
  else 
    echo "" >> $logfile
    echo "Ping failed: The $LB_HOST is not accessible! "  >> $logfile
    echo "" >> $logfile
    echo " LB Basic Test:                      Failed. " >> $logfile
    exit $TEST_ERROR
  fi
#  echo "<font color="green"> - OK </font>"
}

check_exec()
{
        [ $DEBUG -gt 0 ] && [ -n "$2" ] && echo -n -e "$2\t" >> $logfile || echo -n -e "$1\t" >> $logfile
        eval $1
        RV=$?
        [ $DEBUG -gt 0 ] && [ $RV -eq 0 ] && echo "OK" >> $logfile || echo "FAILED" >> $logfile
        return $RV
}

#
# check the binaries
#########################
check_binaries()
{
 check_exec 'LBJOBREG=`which $LBJOBREG`' "Checking binary $LBJOBREG ? " || exit 1
 check_exec 'LBJOBLOG=`which $LBJOBLOG`' "Checking binary $LBJOBLOG ? " || exit 1
 check_exec 'LBLOGEV=`which $LBLOGEV`' "Checking binary $LBLOGEV ?" || exit 1
 check_exec 'LBUSERJOBS=`which $LBUSERJOBS`' "Checking binary $LBUSERJOBS ?" || exit 1
 check_exec 'LBJOBSTAT=`which $LBJOBSTAT`' "Checking binary $LBJOBSTAT ? " || exit 1
 check_exec 'LBCHANGEACL=`which $LBCHANGEACL`' "Checking binary $LBCHANGEACL ?" || exit 1
 check_exec 'LBMON=`which $LBMON`' "Checking binary $LBMON       " || exit 1
}
#
# check the services
##################"
check_services()
{
echo "Listening to locallogger port (9002)" >> $logfile
./testSocket $LB_HOST 9002 >> $logfile
if [ $? -eq 0 ]; then
 echo "logd running ? -                         [OK]" >> $logfile
 else 
    echo "logd running ? -                      [FAILED]" >> $logfile
    exit $TEST_ERROR
  fi
echo "Listening to interlogger ports (9000-9001-9003)" >> $logfile
./testSocket $LB_HOST 9000 >> $logfile &&
./testSocket $LB_HOST 9001 >> $logfile &&
./testSocket $LB_HOST 9003 >> $logfile 
if [ $? -eq 0 ]; then
 echo "Inetrlogd running ? -               [OK]" >> $logfile
 else 
    echo "interlogd running ? -            [FAILED]" >> $logfile
    exit $TEST_ERROR
  fi
}

#####################
#  Starting the test
#####################
ping_host
check_binaries
check_services
if [ $flag -ne 1 ];then
	cat $logfile
	rm $logfile
fi

