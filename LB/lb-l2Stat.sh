#!/bin/bash
# Normal event delivery and Normal Job States with internal BKsrever performance

#Prerequisities: All services running 
#Actions:
#Registers jobs with glite-lb-job-reg prferably pointing to remote LB Server
#Check of the job status
#Logs sequences of events with glite-lb-logevent
#Check with glite-lb-job_status that the status of the jobs are correct and mesures how long it took to get results


PATH=/opt/glite/examples:$PATH
#echo $PATH
LBJOBREG=${LBJOBREG:-glite-lb-job_reg}
LBLOGEVENT=${LBLOGEVENT:-glite-lb-logevent}
LBJOBSTATUS=${LBJOBSTATUS:-glite-lb-job_status}
LBJOBLOG=${LBJOBLOG:-glite-lb-job_log}
LBJOBSTAT=${LBJOBSTAT:-glite-lb-job_status}
LBPURGE=${PURGE:-glite-lb-purge}

# -m host
BKSERVER="pc900.iihe.ac.be"
STATES="aborted cancelled done ready running scheduled waiting submitted "
SOURCES="NetworkServer WorkloadManager BigHelper JobController LogMonitor LRMS Application UserInterface"

stest=1
i=0
JOBS_ARRAY_SIZE=10
# timeouts for polling the bkserver
timeout=10
maxtimeout=300
NB_TAGS=50
INTERVAL=2

init()
{
export EDG_WL_QUERY_SERVER="$BKSERVER:9000"
export EDG_WL_LOG_DESTINATION="$BKSERVER:9002"
BKSERVER_HOST="$BKSERVER:9000"
BKSERVER_OPT="-m $BKSERVER"
}

get_time()
{
    sec=`date +%s`
    nsec=`date +%N`
    time=`echo "1000000000*$sec + $nsec"|bc`
#    time=$sec
    return 0
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
eval $LBJOBREG -m pc900.iihe.ac.be:9000  -s userInterface > jobreg
getJobId
job=`cat jobreg`
rm jobreg
}

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

#job status test
testLBP()
{
echo "Checking the Events............................................."
echo
job_id=0
while [ $job_id -lt $JOBS_ARRAY_SIZE ] ; do
	get_time
	start=$time
	logEvent $job_id
	logTag $job_id
	
	
	eval $LBJOBSTATUS ${SAMPLE_JOBS_ARRAY[$job_id]} > status
        testStatus=`cat status |grep -i state.*${SAMPLE_JOBS_STATES[$job_id]}|wc -l`
	response=0
        while [ $testStatus -ne 1 ];do
		bkserver_state=`cat status |grep -i state.*${SAMPLE_JOBS_STATES[$job_id]}`
		testStatus=`cat status |grep -i state.*${SAMPLE_JOBS_STATES[$job_id]}|wc -l`
		echo "**Retrying**"
		sleep $timeout
		response=$(($response + $timeout ))
		if test $response -gt $maxtimeout ; then
			echo -e "ERROR\n\tstatus of job ${SAMPLE_JOBS_ARRAY[$job_id]} as queried from bkserver ($bkserver_state) has not become ${SAMPLE_JOBS_STATES[$job_id]} for more than $response seconds!"
			echo "Detailed status has been copied to errorStatus.tmp"
                	echo
                	dtest=0
			exit 1;
		fi	
	done
	get_time
	response=`echo "scale=9; ($time - $start)/1000000000"|bc`
	SAMPLE_JOBS_RESPONSES[$job_id]=$response
        echo "Job: $job_id ....[`cat status |grep -i state.*${SAMPLE_JOBS_STATES[$job_id]}`].......[OK]"
	echo
	rm status
        job_id=$[$job_id+1]
	done
	j=0
        total=0
        echo "Sending events took for individual jobs the following time"
        while [ $j -lt $JOBS_ARRAY_SIZE ] ; do
                total=`echo "scale=9; $total + ${SAMPLE_JOBS_RESPONSES[$j]}" |bc`
                echo -e "${SAMPLE_JOBS_ARRAY[$j]} \t${SAMPLE_JOBS_RESPONSES[$j]} seconds"
                        j=$(($j + 1))
        done
	echo -e "Total time for $JOBS_ARRAY_SIZE jobs: \t$total"
	echo -e -n "Average time for event: \t" 
	echo "scale=9; $total / $JOBS_ARRAY_SIZE "|bc
	 echo -e -n "Average time for event and tags: \t" 
        echo "scale=9; $total / $JOBS_ARRAY_SIZE / $NB_TAGS"|bc
	echo -e -n "Event throughput (events/sec): \t"
	echo "scale=9; $NB_TAGS * $JOBS_ARRAY_SIZE / $total"|bc
	echo
	echo "A detailed list of events logged has been printed to LoggedEvents.log"
	echo
}

showHelp()
{
        echo  "Usage: $0 [OPTIONS] "
        echo  "Options:"
        echo  " -h | --help                   Show this help message."
	echo  " -n | --nbjobs                 Number of jobs"
        echo  " -s | --states                 List of states in which could tested jobs fall."
	echo  " -m | --bkserver               Host address of the BKServer "
	echo  " -t | --tags                   Number of user tags to load to each job."
	echo  " -l | --large-stress 'size'    Do a large stress logging ('size' rand om data added to the messages."
        echo  ""

#       echo  "For proper operation check your grid-proxy-info"
#       grid-proxy-info
}

logEvent()
#ARG1: Number of the job considered in the jobs array
{
st_count=`echo $STATES | wc -w`
tmp=`echo $RANDOM % $st_count + 1 | bc`
state=`echo $STATES | cut -d " " -f $tmp | tr A-Z a-z`
SAMPLE_JOBS_STATES[$1]=$state
echo "Logging event to the job($1).........................[$state]"
echo > LoggedEvents.log
echo "Submitting events to the job: ${SAMPLE_JOBS_ARRAY[$1]} " >> LoggedEvents.log
echo >> LoggedEvents.log
echo "event submitted.......................................[$state]" >> LoggedEvents.log
eval glite-lb-$state.sh $LARGE_STRESS -j ${SAMPLE_JOBS_ARRAY[$1]} 2>out
}
logTag()
{
i=0
echo "Logging $NB_TAGS tags to the job................"
eval $LBLOGEVENT -s Application -n $NB_TAGS -e UserTag -j ${SAMPLE_JOBS_ARRAY[$1]} -name testTag -value 12345  >> LoggedEvents.log
}



#input
if [ -z "$1" ]; then
  showHelp
  exit 2
fi
while test -n "$1"
do
        case "$1" in
        "-h" | "--help") showHelp && exit 2 ;;
	"-n" | "--nbjobs") shift ; JOBS_ARRAY_SIZE=$1 ;;
	"-s" | "--states") shift; STATES="$1" ;;
        "-m" | "--bkserver") shift ; BKSERVER_HOST=$1 ;;
	"-t" | "--tags") shift ; NB_TAGS=$1 ;;
	"-l" | "--large-stress") shift ; LARGE_STRESS="-l $1" ;;
#       "-g" | "--log") shift ; logfile=$1 ;;

        *) echo "Unrecognized option $1 try -h for help"; exit 2 ;;

        esac
        shift
done

echo "Test of job status with several jobs "
echo "***********************************"
echo
init
array_job_reg
testLBP
echo
if [ $stest -eq 1  ];then
        echo "Final test result .........................................[OK]"
	exit 1
else 	echo "Final test result .........................................[FAILED]"
	exit 0
 fi
echo
