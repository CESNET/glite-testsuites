$Header$
Readme file for lb1 v1.0

lb-l1.sh
********

Script for level 1 testing of LB server

* Prerequisities: 
   - LB server running (user does not have to get any credentials)
   - the following environment variables set:

     GLITE_LOCATION - PATH to gLite software
     SAME_SENSOR_HOME - PATH to sensors (might be set to "." for testSocket sensor)
     GLITE_LB_SERVER_PORT - if nondefault port (9000) used

* Basic test:
   ping_host() - basic network ping
   check_binaries() - check for binary executables, calls check_exec()
   check_socket() - TCPecho to host:port for all three LB server ports
        (by default 9000 for logging, 9001 for querying, 9003 for web services)

Usage: lb-l1.sh [OPTIONS] host
Options:
 -h | --help            Show this help message.
 -o | --output 'file'   Redirect all output to the 'file' (stdout by default).
 -t | --text            Format output as plain ASCII text.
 -c | --color           Format output as text with ANSI colours (autodetected by default).
 -x | --html            Format output as html.

* The name of the LB server host has to be specified everytime
 
 
Examples
********

$ ./lb-l1.sh sci.civ.zcu.cz
Jul 30 15:01:21 scientific lb-l1.sh:                                 start 
Testing ping to LB server sci.civ.zcu.cz                             done
Testing LB binaries:
  checking binary glite-lb-logevent                                  done
  checking binary glite-lb-job_log                                   done
  checking binary glite-lb-job_reg                                   done
  checking binary glite-lb-user_jobs                                 done
  checking binary glite-lb-job_status                                done
  checking binary glite-lb-change_acl                                done
Testing LB server at sci.civ.zcu.cz:9000 (logging)                   done
Testing LB server at sci.civ.zcu.cz:9001 (queries)                   done
Testing LB server at sci.civ.zcu.cz:9003 (web services)              done
Jul 30 15:01:21 scientific lb-l1.sh:                                 end 

