$Header$
Readme file for lb1 v1.0

lb-l1.sh
********

Script for testing of LB services 

* Prerequisities: 
   - All services running (user does not have to get any credentials)
   - the following environment variables set:

     GLITE_WMS_LOG_DESTINATION - address of local logger, in form 'host:port'
     GLITE_WMS_QUERY_SERVER - address of LB server, in form 'host:port'

* Basic test:
   PING
   check LB binaries
   check running services

Usage: lb-l1.sh [OPTIONS] host
Options:
 -h | --help            Show this help message.
 -o | --output 'file'   Redirect all output to the 'file' (stdout by default).
 -t | --text            Format output as plain ASCII text.
 -c | --color           Format output as text with ANSI colours (autodetected by default).
 -x | --html            Format output as html.

* The name of the bkserver host has to be specified everytime
 
 
Examples
********

$ ./lb-l1.sh -o log scientific.civ.zcu.cz

Jul 29 21:57:24 scientific lb-l1.sh:                                 start 
Testing ping to LB server sci.civ.zcu.cz                             done
Testing LB binaries:
  checking binary glite-lb-logevent                                  done
  checking binary glite-lb-job_log                                   done
  checking binary glite-lb-job_reg                                   done
  checking binary glite-lb-user_jobs                                 done
  checking binary glite-lb-job_status                                done
  checking binary glite-lb-change_acl                                done
Testing LB services                                                  skipped
Jul 29 21:57:26 scientific lb-l1.sh:                                 end 

