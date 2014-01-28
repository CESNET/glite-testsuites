#!/bin/bash
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

# show help and usage

#!/bin/bash
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

# show help and usage
progname=`basename $0`
showHelp()
{
cat << EndHelpHeader
Testing proxy delegation via proxyput

https://github.com/CESNET/gridsite/issues/2

Prerequisities:
   - GridSite and httpd with mod_ssl installed and launched
   - Generated fake certificates and proxy certificate(voms-proxy-init)

Returned values:
    Exit TEST_OK: Test Passed
    Exit TEST_ERROR: Test Failed
    Exit 2: Wrong Input

EndHelpHeader

        echo "Usage: $progname [OPTIONS]"
        echo "Options:"
        echo " -h | --help            Show this help message."
        echo " -t | --text            Format output as plain ASCII text."
        echo " -c | --color           Format output as text with ANSI colours (autodetected by default)."
        echo " -x | --html            Format output as html."
}

# read common definitions and functions
for COMMON in gridsite-common.sh ../../LB/tests/lb-common.sh
do
        if [ ! -r ${COMMON} ]; then
                printf "Common definitions '${COMMON}' missing!"
                exit 2
        fi
        source $COMMON
done

while test -n "$1"
do
        case "$1" in
                "-h" | "--help") showHelp && exit 2 ;;
                "-t" | "--text")  setOutputASCII ;;
                "-c" | "--color") setOutputColor ;;
                "-x" | "--html")  setOutputHTML ;;
        esac
        shift
done

##
#  Starting the test
#####################

test_start

# check_binaries
printf "Testing if all binaries are available"
check_binaries rm htproxyput chown ls
if [ $? -gt 0 ]; then
        test_failed
        test_end
        exit 2
else
        test_done
fi

UPROXY="/tmp/x509up_u`id -u`"
NEWUPROXYDIR="/var/www/proxycache"

printf "Test proxy delegation\n"

if [ ! -e /var/www/proxycache ]; then
        mkdir /var/www/proxycache
fi

if getent passwd www-data >/dev/null; then
        HTTPD_USER=www-data
else
        HTTPD_USER=apache
fi

chown $HTTPD_USER ${NEWUPROXYDIR}

#if the dir is not empty, empty it
rm -rf /var/www/proxycache/*

#delegate the proxy
id=`htproxyput --cert ${UPROXY} --key ${UPROXY} --capath /etc/grid-security/certificates https://$(hostname -f)/gridsite-delegation.cgi`
printf "id: $id"
if [ $? -eq 0 -a -n "$id" ]; then
       test_done
else
        test_failed
fi

#check that the new proxy file was created
#TODO check that proxycache/% always begins with '%'
printf "new proxy file: "
ls /var/www/proxycache/%*/*/userproxy.pem
if [ $? -eq 0 ]; then
       test_done
else
        test_failed
fi

test_end

exit $TEST_OK
