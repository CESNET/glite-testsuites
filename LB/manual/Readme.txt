$Header$

Readme file for basic LB Integration tests 

Service ping tests:
===================

Prerequisities for all service ping tests:
-----------------------------
- the following environment variables set:

   GLITE_LOCATION - PATH to gLite software
   SAME_SENSOR_HOME - PATH to sensors (might be set to "." for testSocket sensor)

- one may also need to run make to build the testSocket binary
  and create link tests -> . (to be used for local SAME_SENSOR_HOME)


lb-test-logger-remote.sh
------------------------
Script for remote testing of LB logger

Run ./lb-test-logger-remote.sh -h for test description and usage.
 
Example:

$ ./lb-test-logger-remote.sh sci.civ.zcu.cz
Aug 13 15:57:02 scientific lb-test-logger-remote.sh:                 start
Testing if all binaries are available                                done
Testing ping to LB logger sci.civ.zcu.cz                             done
Testing LB logger at sci.civ.zcu.cz:9002 (logging)                   done
Aug 13 15:57:04 scientific lb-test-logger-remote.sh:                 end



lb-test-server-remote.sh
------------------------
Script for remote testing of LB server

Run ./lb-test-server-remote.sh -h for test description and usage.
 
Example:

$ ./lb-test-server-remote.sh sci.civ.zcu.cz
Aug 13 15:58:22 scientific lb-test-server-remote.sh:                 start
Testing if all binaries are available                                done
Testing ping to LB server sci.civ.zcu.cz                             done
Testing LB server at sci.civ.zcu.cz:9000 (logging)                   done
Testing LB server at sci.civ.zcu.cz:9001 (queries)                   done
Testing LB server at sci.civ.zcu.cz:9003 (web services)              done
Aug 13 15:58:26 scientific lb-test-server-remote.sh:                 end



lb-test-server-local.sh
-----------------------
Script for testing an LB server running locally

Run ./lb-test-server-local.sh -h for test description and usage.
 
Example:

$ lb-test-server-local.sh
Oct 22 10:59:17 scientific lb-test-server-local.sh:				start 
Testing if all binaries are available						done
Testing if mySQL is running							done
Testing if mySQL is accessible							done
Testing if LB Server is running							done
Testing if LB Server is listening on port 9010					done
Testing if LB Server is listening on port 9011					done
Testing if LB Server is listening on port 9013					done
Testing if Interlogger is running						done
Testing if interlogger is listening on socket /tmp/intelogger_sustr.sock	done
Oct 22 10:59:17 scientific lb-test-server-local.sh:				end 



lb-test-logger-local.sh
-----------------------
Testing a local logger and interlogger running on a local machine.

Run ./lb-test-logger-local.sh -h for test description and usage.
 
Example: 

$ lb-test-logger-local.sh 
Oct 22 11:02:04 scientific lb-test-logger-local.sh:				start 
Testing if all binaries are available						done
Testing if LB logger is running							done
Testing if LB logger is listening on port 9012					done
Testing if Interlogger is running						done
Testing if interlogger is listening on socket /tmp/intelogger_sustr.sock	done
Oct 22 11:02:05 scientific lb-test-logger-local.sh:				end 


System Functionality Tests
==========================

Prerequisities for all system functionality tests:
-----------------------------
- the following environment variables set:

   GLITE_WMS_QUERY_SERVER - LB server address:port
   GLITE_LOCATION - PATH to gLite software
   SAME_SENSOR_HOME - PATH to sensors (might be set to "." for testSocket sensor)

- one may also need to run make to build the testSocket binary
  and create link tests -> . (to be used for local SAME_SENSOR_HOME)


lb-test-job-registration.sh
---------------------------
Tests if it is possible to register jobs and query for their states. 

Example:

$ lb-test-job-registration.sh
Oct 22 11:32:18 scientific lb-test-job-registration.sh:								start 
Testing if all binaries are available										done
Testing credentials												done
Registering testing job												done
Is the testing job (https://scientific.civ.zcu.cz:9010/jf1Mgogl4-FvdQdrPe0a4Q) in a correct state? Submitted	done
Oct 22 11:32:19 scientific lb-test-job-registration.sh:								end 



lb-test-event-delivery.sh
-------------------------
Tests jobs registration, event deliver and proper state modification.

Example:

$ lb-test-event-delivery.sh 
Oct 22 14:14:43 scientific lb-test-event-delivery.sh:								start 
Testing if all binaries are available										done
Testing credentials												done
Registering testing job												done
Registered job: https://scientific.civ.zcu.cz:9010/jiOm5Wy7w4Q34JcOqVv_jQ
Logging events resulting in READY state
Sleeping for 10 seconds (waiting for events to deliver)...
Is the testing job (https://scientific.civ.zcu.cz:9010/jiOm5Wy7w4Q34JcOqVv_jQ) in a correct state? Ready	done
Logging events resulting in RUNNING state
Logging events resulting in DONE state
Sleeping for 10 seconds (waiting for events to deliver)...
Testing job (https://scientific.civ.zcu.cz:9010/jiOm5Wy7w4Q34JcOqVv_jQ) is in state: Done			done
Oct 22 14:15:07 scientific lb-test-event-delivery.sh:								end 

