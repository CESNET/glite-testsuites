Readme file for lb2 v1.0*************************************
Date: 19.03.2007					*		
Author:							*
*************************************************************

lb-l2.sh
********

Normal event delivery and Normal Job States 

* Prerequisities: All services running (LBProxy not used), user must have a valid proxy on the UI

* Test:
Registers jobs with glite-lb-job-reg preferably pointing to remote LB Server
Check of the job status
Logs sequences of events with glite-lb-..... sh scripts (ex: gite-lb-ready.sh)
Checks with glite-lb-job_log that the events got delivered aftewards
Checks with glite-lb-job_status that the status of the jobs are correct
       
* Options:       
echo  " -h | --help                   Show this help message."        
echo  " -r | --retries                Number of test retries (2 by default)"        
echo  " -n | --nbjobs                 Number of jobs (10 by default)"        
echo  " -m | --bkserver               Host address of the BKServer ex:pc900.iihe.ac.be "        
echo  " -s | --states                 List of states in which could tested jobs fall."        
echo  " -l | --large-stress 'size'    Do a large stress logging ('size' random data added to the messages."


* The name of the bkserver has to be specified everytime

* The option -l 'size' addes random data to the messages send to the BKServer with glite-lb-logevent. 

* With the option -s you can specify the list of states that will be submitted randomly to the jobs created

* When you specify a state, the script will send all the events the job has to pass trough.



lb-l2Stat.sh
************

* This script is mainly the same than lb-l2.sh but it includes a mesure of time. 

* You can specify one more option

 echo  " -t | --tags                   Number of user tags to load to each job."
 




examples
********

./lb-l2.sh -n 4 -m gliterb.iihe.ac.be -s "Running Done"

Registering 4 jobs....................
https://pc900.iihe.ac.be:9000/3E8xyyH_FCb4z1rN5TymFw
https://pc900.iihe.ac.be:9000/aTLnW6Mmm_whpt_tbxHjPQ
https://pc900.iihe.ac.be:9000/TnuSJvVZCLcYDDv1GXdocw
https://pc900.iihe.ac.be:9000/WW-0FU8g4tID1TMMPZCEBg
Logging events to the 4 jobs....................................

Logging tags to the 4 jobs....................................

Checking the Events.............................................
Job 0 ....................[OK]
Job 1 ....................[OK]
Job 2 ....................[OK]
Job 3 ....................[OK]

A detailed list of the sequence of events logged to each job has been printed to 1174296170.log

Checking the Jobs Status........................................

Job: 0 ..Logged state:running-Recorded state : Running.......[OK]
Job: 1 ..Logged state:done-Recorded state : Done.......[OK]
Job: 2 ..Logged state:done-Recorded state : Done.......[OK]
Job: 3 ..Logged state:done-Recorded state : Done.......[OK]

Final test result .........................................[OK]


1174296170.log (this file contains a detailed list of the sequence of events logged to each job during the test)

...
Events Sent.....
     1  UserTag
     2  RegJob
     3  Accepted
     4  EnQueued
     5  DeQueued
     6  HelperCall
     7  Match
     8  HelperReturn
     9  EnQueued
    10  DeQueued
    11  Transfer
    12  Accepted
    13  Transfer
    14  Running
    15  Done
Events recorded in the LB server.....
     1  UserTag
     2  RegJob
     3  Accepted
     4  EnQueued
     5  DeQueued
     6  HelperCall
     7  Match
     8  HelperReturn
     9  EnQueued
    10  DeQueued
    11  Transfer
    12  Accepted
    13  Transfer
    14  Running
    15  Done
...



./lb-l2Stat.sh -n 3 -m gliterb.iihe.ac.be
...
Sending events took for individual jobs the following time
https://pc900.iihe.ac.be:9000/QZUecSg86IXtZeMmU4Rd6Q    11.061101000 seconds
https://pc900.iihe.ac.be:9000/-R0CDDoicKdwqAZHEI32gA    9.438249000 seconds
https://pc900.iihe.ac.be:9000/x6qFebsaNOR1a31NlAhJIQ    3.167140000 seconds
Total time for 3 jobs:  23.666490000
Average time for event:         7.888830000
Average time for event and tags:        .157776600
Event throughput (events/sec):  6.338075481
...


List of possible job Status 
***************************

"Submitted Waiting Ready Cancelled Scheduled Aborted Running Done Cleared"

* Submitted: The job has been submitted by the user but not yet processed by the Network Server

* Waiting: The job has been accepted by the Network Server but not yet processed by the workload manager

* Ready: The job has been assigned to a Computing Element but not yet transferred to it

* Scheduled: The job is wainting in the CE's queue

* Running: The job is running

* Done: The job has finished

* Aborted: The job has been aborted by the WMS (it was too long or the proxy certificate expired)

* Cancelled: The job has been cancelled by the user

* Cleared: The output sandbox has been transferred to the UserInterface

