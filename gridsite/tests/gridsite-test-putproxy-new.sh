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
COMMON=`dirname $0`/gridsite-common.sh
if [ ! -r ${COMMON} ]; then
        printf "Common definitions '${COMMON}' missing!\n"
        exit 2
fi
source $COMMON

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

# The proxy that gets delegated comes from 'make -C tools' now, and the cache the
# server keeps what it receives in comes from setup.sh; this script used to decide
# both for itself (/tmp/x509up_u<n> and a mkdir of /var/www/proxycache as root).
printf "Test proxy delegation\n"

if [ ! -d "$GS_PROXYCACHE" ]; then
        printf "Proxy cache $GS_PROXYCACHE"
        test_skipped
        print_error "is not present - setup.sh creates it (docs/gridsite.md)"
        test_end
        exit $TEST_OK
fi

gs_chown "$GS_HTTPD_USER" "$GS_PROXYCACHE" \
        || print_warning "could not change ownership; relying on the access rights setup.sh gave it"

#if the dir is not empty, empty it. The redirect is for the empty case, where the
#glob is passed to rm unchanged.
rm -rf $GS_PROXYCACHE/* 2> /dev/null

#delegate the proxy
id=`htproxyput --cert "$X509_USER_PROXY" --key "$X509_USER_PROXY" --capath "$GS_CAPATH" https://$GS_SERVER/gridsite-delegation.cgi`
printf "id: $id"
# Only whether an id came back; the other half of this condition used to be the
# exit status of the printf above it, which cannot fail.
if [ -n "$id" ]; then
       test_done
else
        test_failed
fi

#check that the new proxy file was created
#TODO check that proxycache/% always begins with '%'
printf "new proxy file: "
ls $GS_PROXYCACHE/%*/*/userproxy.pem
if [ $? -eq 0 ]; then
       test_done
else
        test_failed
fi

test_end

exit $TEST_OK
