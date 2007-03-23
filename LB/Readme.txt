

Readme file for lb1 v1.0*************************************
Date: 19.03.2007					*		
Author:							*
*************************************************************

lb-l1.sh
********

Script for testing of LB services 

* Prerequisities: All services running (user does not have to get any credentials)

* Basic test:	PING
				check LB binaries
				check running services
* Options:
 -h | --help                   Show this help message.
 -m | --m lb_host
 -g | --log 'logfile'          Redirect all output to the 'logfile'.
 
* The name of the bkserver has to be specified everytime
 
 
Examples
********

[ui] /home/fmunster> ./lb-l1.sh -g log
USAGE: TCPecho <server_ip> <port>

[ui] /home/fmunster> ./lb-l1.sh -g log -m gliterb.iihe.ac.be

[ui] /home/fmunster> cat log

Basic services test......
Checking binary glite-lb-job_reg ?      OK
Checking binary glite-lb-job_log ?      OK
Checking binary glite-lb-logevent ?     OK
Checking binary glite-lb-user_jobs ?    OK
Checking binary glite-lb-job_status ?   OK
Checking binary glite-lb-change_acl ?   OK
Checking binary glite-lb-lbmon          OK
Listening to locallogger port (9002)
Connecting a socket with : 193.190.246.245,9002 [OK]
glite-lb-logd running ? -                         [OK]
Listening to interlogger ports (9000-9001-9003)
Connecting a socket with : 193.190.246.245,9000 [OK]
Connecting a socket with : 193.190.246.245,9001 [OK]
Connecting a socket with : 193.190.246.245,9003 [OK]
Interlogd running ? -               [OK]


