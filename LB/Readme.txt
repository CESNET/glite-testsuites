$Header$

Readme file for basic LB Integration tests 

Service ping tests:
===================

Prerequisities for all tests:
-----------------------------
- the following environment variables set:

   GLITE_LOCATION - PATH to gLite software
   SAME_SENSOR_HOME - PATH to sensors (might be set to "." for testSocket sensor)

- one may also need to run:

$ make
$ ln -s . tests


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

