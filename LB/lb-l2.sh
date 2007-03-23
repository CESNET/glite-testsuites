#!/bin/bash
#3.1.4 et 3.2.1: Normal event delivery and Normal Job States

#Prerequisities: All services running 

#Actions:
#Registers jobs with glite-lb-job-reg prferably pointing to remote LB Server
#Check of the job status
#Logs sequences of events with glite-lb-logevent
#Checks with glite-lb-job_log that the events got delivered aftewards
#Checks with glite-lb-job_status that the status of the jobs are correct


PATH=/opt/glite/examples:$PATH
#echo $PATH
LBJOBREG=${LBJOBREG:-glite-lb-job_reg}
LBLOGEVENT=${LBLOGEVENT:-glite-lb-logevent}
LBJOBSTATUS=${LBJOBSTATUS:-glite-lb-job_status}
LBJOBLOG=${LBJOBLOG:-glite-lb-job_log}
LBJOBSTAT=${LBJOBSTAT:-glite-lb-job_status}
LBPURGE=${PURGE:-glite-lb-purge}

BKSERVER="localhost"
STATES="aborted cancelled done ready running scheduled waiting submitted "
SOURCES="NetworkServer WorkloadManager BigHelper JobController LogMonitor LRMS Application UserInterface"

dtest=1
i=0
JOBS_ARRAY_SIZE=10
INTERVAL=2
DATE_S=`date +"%s"`
DATE=`date`
LOG_FILE="$DATE_S.log"


init()
{
echo "Date: $DATE" > $LOG_FILE
export EDG_WL_QUERY_SERVER="$BKSERVER:9000"
export EDG_WL_LOG_DESTINATION="$BKSERVER:9002"
BKSERVER_HOST="$BKSERVER:9000"
BKSERVER_OPT="-m $BKSERVER"
}


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
        echo "UserTag"> events
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
        if [$testStatus -eq 1 ] ; then
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

#logging tags to the jobs
logTags()
{
echo "Logging tags to the $JOBS_ARRAY_SIZE jobs...................................."
echo

job_id=0
while [ $job_id -lt $JOBS_ARRAY_SIZE ] ; do
        eval $LBLOGEVENT -s Application -e UserTag -j ${SAMPLE_JOBS_ARRAY[$job_id]} -name testTag -value 12345  >> $LOG_FILE
job_id=$[$job_id+1]
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
init
array_job_reg
logEvents
logTags
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
