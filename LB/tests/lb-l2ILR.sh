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
#3.1.3: Interlogger Recovery
##############################################################################################
#Prerequisities: locallogger(glite-lb-logd) and BKServer (glite-lb-bkserv) must be running.
#The interlogger(glite-lb-interl) must be stopped. (kill the process manually on the LB machine)

#Actions:
#Registers jobs with glite-lb-job-reg 
#Logs sequences of events with glite-lb-logevent
#User starts the interlogger daemon
#(/opt/glite/etc/config/scripts/glite-lb-cofig.py --start on your LB machine (as root))
#Checks with glite-lb-job_log that the events got delivered aftewards 
#by the interloger to the bookkeeping server. (from the localloger which is linked to the WMS)
#Checks with glite-lb-job_status that the status of the jobs are correct in the BKserver
###############################################################################################

PATH=/opt/glite/examples:$PATH
#echo $PATH
LBJOBREG=${LBJOBREG:-glite-lb-job_reg}
LBLOGEVENT=${LBLOGEVENT:-glite-lb-logevent}
LBJOBSTATUS=${LBJOBSTATUS:-glite-lb-job_status}
LBJOBLOG=${LBJOBLOG:-glite-lb-job_log}
LBJOBSTAT=${LBJOBSTAT:-glite-lb-job_status}
LBPURGE=${PURGE:-glite-lb-purge}

STATES="aborted cancelled done ready running scheduled waiting submitted "
SOURCES="NetworkServer WorkloadManager BigHelper JobController LogMonitor LRMS Application UserInterface"
dtest=1
i=0
JOBS_ARRAY_SIZE=10
INTERVAL=2
DATE_S=`date +"%s"`
DATE=`date`
LOG_FILE="$DATE_S.log"

#initialisation
init()
{
echo "Date: $DATE" > $LOG_FILE
export EDG_WL_QUERY_SERVER="$BKSERVER:9000"
export EDG_WL_LOG_DESTINATION="$BKSERVER:9002"
BKSERVER_HOST="$BKSERVER:9000"
BKSERVER_OPT="-m $BKSERVER"
}

#extracting the job id 
getJobId()
{
cat jobreg |grep "EDG_JOBID" |cut -c12- > jobList2
res=`cat jobList2 |wc -c`
res=$[$res-2]
cat jobList2 |cut -c1-`echo $res` > jobreg
rm jobList2
}

#registrating a job
job_reg()
{
eval $LBJOBREG $BKSERVER_OPT -s $1 > jobreg
getJobId
job=`cat jobreg`
rm jobreg
}

#registering a list of jobs which jobid's are placed in an array
array_job_reg()
{
echo "Registering $JOBS_ARRAY_SIZE jobs...................."
job_id=0
st_count=`echo $SOURCES | wc -w`
while [ $job_id -lt $JOBS_ARRAY_SIZE ] ; do
        tmp=`echo $RANDOM % $st_count + 1 | bc`
        jsource=`echo $SOURCES | cut -d " " -f $tmp | tr A-Z a-z`
        job_reg $jsource
        echo $job
        SAMPLE_JOBS_ARRAY[$job_id]=$job
        job_id=$[$job_id+1]
        done
}

#Event delivery  test
testLB()
{
echo "Checking the Events............................................."
echo
job_id=0
while [ $job_id -lt $JOBS_ARRAY_SIZE ] ; do
        #sleep 2
        #out is the list of events sent, we count the number of events and then we extract the job status
        nbEvents=`cat out[$job_id] |grep glite-lb-logevent | wc -l`
        nbEvents=$[$nbEvents+1]
        cat out[$job_id] |gawk -F"-e " '{ print $2 }' > eventsTemp
        echo "RegJob">> events
        cat eventsTemp|gawk -F" --" '{ print $1 }'>> events
        rm eventsTemp
        events3="blank"
        i=0
        cmp -s events events3
        while [ $? -ne 0 ] && [ $i -lt $INTERVAL ] ; do


        #we use glite-lb-job_log and apply the same treatment as above to the output
                eval $LBJOBLOG -r $INTERVAL -d 2  ${SAMPLE_JOBS_ARRAY[$job_id]} > joblog2
                nbevents=`cat joblog2 | grep DATE | wc -l`
                cat joblog2|gawk -F"DG.EVNT=\"" '{ print $2 }' > eventsTemp2
                cat eventsTemp2|gawk -F"\"" '{ print $1 }'> events2
                cat events2|sed /^$/d > events3
                rm eventsTemp2 events2 joblog2
                #Comparison of the outputs and intermediary printout
                echo "Events Sent....." >> $LOG_FILE
                cat -n events >> $LOG_FILE
#               cat -n events
                echo "Events recorded in the LB server....." >> $LOG_FILE
                cat -n events3 >> $LOG_FILE
#               cat -n events3
                i=$[$i+1]
                cmp -s events events3
        done
        cmp -s events events3
        if [ $? -eq 0 ]; then
                echo "Job $job_id ....................[OK]"  
                i=0

        else
                echo "Job $job_id.....................[FAILED]" 
                dtest=0
        fi
        rm events events3 out[$job_id]
        job_id=$[$job_id+1]
done
echo
echo "A detailed list of events logged has been printed to $LOG_FILE"
echo
}

#job status test
testLB2()
{
echo "Checking the Jobs Status........................................" 
echo
job_id=0
 while [ $job_id -lt $JOBS_ARRAY_SIZE ] ; do
        #sleep 1
        eval $LBJOBSTATUS ${SAMPLE_JOBS_ARRAY[$job_id]} > status
        testStatus=`cat status |grep -i state.*${SAMPLE_JOBS_STATES[$job_id]}|wc -l`
        i=0
        while [ $testStatus -ne 1 ] && [ $i -lt $INTERVAL ] ; do
                bkserver_state=`cat status |grep -i state.*${SAMPLE_JOBS_STATES[$job_id]}`
                testStatus=`cat status |grep -i state.*${SAMPLE_JOBS_STATES[$job_id]}|wc -l`
                i=$[$i+1]
        done
        if [ $testStatus -eq 1 ] ; then
                echo "Job: $job_id ..Logged state:${SAMPLE_JOBS_STATES[$job_id]}-Recorded `cat status |grep -i state.*${SAMPLE_JOBS_STATES[$job_id]}`.......[OK]"
        else
                echo "Job: $job_id ..Logged state:${SAMPLE_JOBS_STATES[$job_id]}-Recorded `cat status |grep -i state.*${SAMPLE_JOBS_STATES[$job_id]}`.......[FAILED]"
                cat status > errorStatus.tmp
                echo "Detailed status has been copied to errorStatus.tmp"
                echo
                dtest=0
        fi
        rm status
job_id=$[$job_id+1]
done
}

#logging events to the jobs. Events are selected randomly from a list.
logEvents()
{
echo "Logging events to the $JOBS_ARRAY_SIZE jobs...................................."
echo
job_id2=0
st_count=`echo $STATES | wc -w`
        while [ $job_id2 -lt $JOBS_ARRAY_SIZE ] ; do
         tmp=`echo $RANDOM % $st_count + 1 | bc`
        state=`echo $STATES | cut -d " " -f $tmp | tr A-Z a-z`
        SAMPLE_JOBS_STATES[$job_id2]=$state
        echo >> $LOG_FILE
        echo "Submitting events to the job: ${SAMPLE_JOBS_ARRAY[$job_id2]} " >> $LOG_FILE
        echo >> $LOG_FILE

        echo "event submitted.......................................[$state]" >> $LOG_FILE
        eval glite-lb-$state.sh $LARGE_STRESS -j ${SAMPLE_JOBS_ARRAY[$job_id2]} 2>out[$job_id2]
        job_id2=$(($job_id2 + 1))
done
}


showHelp()
{        
echo  "Usage: $0 [OPTIONS] "        
echo  "Options:"        
echo  " -h | --help                   Show this help message."        
echo  " -r | --retries                Number of test retries (2 by default)"        
echo  " -n | --nbjobs                 Number of jobs (10 by default)"        
echo  " -m | --bkserver               Host address of the BKServer ex:pc900.iihe.ac.be "        
echo  " -s | --states                 List of states in which could tested jobs fall."        
echo  " -l | --large-stress 'size'    Do a large stress logging ('size' random data added to the messages."
echo  ""

#       echo  "For proper operation check your grid-proxy-info"
#       grid-proxy-info
}


#input
if [ -z "$1" ]; then
  showHelp
  exit 2
fi
BK=0
while test -n "$1"
do
        case "$1" in
        "-h" | "--help") showHelp && exit 2 ;;
        "-r" | "--retries") shift ; INTERVAL=$1 ;;
        "-n" | "--nbjobs") shift ; JOBS_ARRAY_SIZE=$1 ;;
        "-m" | "--bkserver") shift ; BKSERVER=$1 BK=1;;
        "-s" | "--states") shift; STATES="$1" ;;
        "-l" | "--large-stress") shift ; LARGE_STRESS="-l $1" ;;
#       "-g" | "--log") shift ; logfile=$1 ;;

        *) echo "Unrecognized option $1 try -h for help"; exit 2 ;;

        esac
        shift
done
if [ $BK -ne 1 ]; then
        echo
        echo "You must specify the hostname of the LB Server with the option -m (ex: -m pf435.ulb.ac.be)" 
        echo
        exit 2
fi
echo


#main..................................................................

#main..................................................................
init
echo "Be sure you have stopped glite-lb-interlogd .........................."
echo "You have to log on on your LB machine and kill the process manually..."
echo "Press any key........................................................."
read x
array_job_reg
logEvents
echo "Please start the glite-lb-interlogd..................................."
echo "Please use /opt/glite/etc/config/scripts/glite-lb-cofig.py --start...."
echo "Press any key........................................................."
read x
echo "Sleeping 10 seconds......................................................"
sleep 10
testLB
testLB2
#testProxy
#eval $LBPURGE -h
echo
if [ $dtest -eq 1  ];then
        echo "Final test result .........................................[OK]"
        exit 1
else    echo "Final test result .........................................[FAILED]"
        exit 0
 fi
echo
