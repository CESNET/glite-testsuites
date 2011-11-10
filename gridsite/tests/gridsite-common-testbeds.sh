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

function gen_arrange_script()
{
remotehost=$1
COPYPROXY=$2

cat << EndArrangeScript > arrange_gridsite_test_root.sh 
CERTFILE=\$1
GLITE_USER=\$2
GSTSTCOLS=\$3
OUTPUT_OPT=\$4

echo "Certificate file: \$CERTFILE "
echo "gLite user:       \$GLITE_USER "
echo "Terminal width:   \$GSTSTCOLS "
echo "Output format:    \$OUTPUT_OPT "

export GSTSTCOLS

yum install -q -y voms-clients
yum install -q -y httpd mod_ssl
sed -e '1,$s!/usr/lib/httpd/modules/!modules/!' /usr/share/doc/gridsite-*/httpd-webserver.conf | sed 's!/var/www/html!/var/www/htdocs!' | sed "s/FULL.SERVER.NAME/$(hostname -f)/" | sed "s/\(GridSiteGSIProxyLimit\)/# \1/"> /tmp/httpd-webserver.conf
echo "AddHandler cgi-script .cgi" >> /tmp/httpd-webserver.conf
echo "ScriptAlias /gridsite-delegation.cgi /usr/sbin/gridsite-delegation.cgi" >> /tmp/httpd-webserver.conf
mkdir /var/www/htdocs
httpd -f /tmp/httpd-webserver.conf

cd /tmp

CVSPATH=\`which cvs\`

if [ "\$CVSPATH" = "" ]; then
        printf "CVS binary not present"
        egrep -i "Debian|Ubuntu" /etc/issue

        if [ \$? = 0 ]; then
                apt-get install --yes cvs
        else
                yum install -y cvs
        fi

fi

if [ $COPYPROXY -eq 1 ]; then
	mv \$CERTFILE x509up_u\`id -u\`
	chown \`id -un\`:\`id -gn\` x509up_u\`id -u\`
else
	rm -rf /tmp/test-certs/grid-security
	cvs -d :pserver:anonymous@glite.cvs.cern.ch:/cvs/jra1mw co org.glite.testsuites.ctb/LB > /dev/null 2>/dev/null
	FAKE_CAS=\`./org.glite.testsuites.ctb/LB/tests/lb-generate-fake-proxy.sh | grep -E "^X509_CERT_DIR" | sed 's/X509_CERT_DIR=//'\`
	if [ "\$FAKE_CAS" == "" ]; then
                echo "Failed generating proxy" >&2
                exit 2
        else
                cp -rv \$FAKE_CAS/* /etc/grid-security/certificates/
        fi
fi

cd ~/
mkdir GridSite_testing
cd GridSite_testing
cvs -d :pserver:anonymous@glite.cvs.cern.ch:/cvs/jra1mw co org.glite.testsuites.ctb/gridsite
cd org.glite.testsuites.ctb/gridsite/tests
echo ========================
echo "  REAL TESTS START HERE"
echo ========================
echo "</verbatim>"
echo "<literal>"
sh ./ping-remote.sh $remotehost \$OUTPUT_OPT
sh ./ping-local.sh \$OUTPUT_OPT -f /tmp/httpd-webserver.conf
sh ./gridsite-test-all.sh \$OUTPUT_OPT
echo "</literal>"
echo "<verbatim>"
echo ==================
echo "  TESTS END HERE"
echo ==================

EndArrangeScript
}

