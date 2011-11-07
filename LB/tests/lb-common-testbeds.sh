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

cat << EndArrangeScript > arrange_lb_test_root.sh 
CERTFILE=\$1
GLITE_USER=\$2
LBTSTCOLS=\$3
OUTPUT_OPT=\$4

export LBTSTCOLS

yum install -q -y globus-proxy-utils 
yum install -q -y postgresql postgresql-server
#Standard setup now uses production brokers. No need to install our own.
#yum install -q -y activemq java-1.6.0-openjdk
yum install -q -y emi-lb-nagios-plugins
yum install -q -y voms-clients

/etc/init.d/postgresql start
mv /var/lib/pgsql/data/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf.orig
cat >/var/lib/pgsql/data/pg_hba.conf <<EOF
local all all trust
host all all 127.0.0.1 ident sameuser
host all all ::1/128 ident sameuser
EOF
/etc/init.d/postgresql reload
createuser -U postgres -S -R -D rtm

#if [ -f ~/.activemqrc ]; then
#	echo ActiveMQ already configured
#else
#	activemq setup ~/.activemqrc
#	activemq start
#fi

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

glite_id=\`id -u \$GLITE_USER\`

echo \$GLITE_USER user ID is \$glite_id

if [ $COPYPROXY -eq 1 ]; then
	mv \$CERTFILE x509up_u\$glite_id
	chown \$GLITE_USER:\$GLITE_USER x509up_u\${glite_id}
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

#Allow glite user to read certain system files. Talk about dirty hacks.
grep -E "$GLITE_USER.*/bin/cat" /etc/sudoers > /dev/null 2> /dev/null
if [ ! \$? = 0 ]; then
	printf "\n$GLITE_USER\tALL=NOPASSWD: /bin/cat /etc/cron.d/glite-lb-purge.cron,/bin/cat /var/log/messages\n\n" >> /etc/sudoers
fi
sed -i /etc/sudoers 's/^Default\srequiretty/#Default requiretty/'

echo cd > arrange_lb_test_user.sh
echo export LBTSTCOLS=\$LBTSTCOLS >> arrange_lb_test_user.sh
echo 'export GLITE_MYSQL_ROOT_PASSWORD="[Edited]"' >> arrange_lb_test_user.sh
echo mkdir LB_testing >> arrange_lb_test_user.sh
echo cd LB_testing >> arrange_lb_test_user.sh
echo cvs -d :pserver:anonymous@glite.cvs.cern.ch:/cvs/jra1mw co org.glite.testsuites.ctb/LB >> arrange_lb_test_user.sh
echo ls >> arrange_lb_test_user.sh
echo cd org.glite.testsuites.ctb/LB/tests >> arrange_lb_test_user.sh
echo ulimit -c unlimited >> arrange_lb_test_user.sh
echo 'export HNAME=\`hostname -f\`' >> arrange_lb_test_user.sh
echo 'export GLITE_WMS_QUERY_SERVER=\$HNAME:9000' >> arrange_lb_test_user.sh
echo 'export GLITE_WMS_NOTIF_SERVER=\$HNAME:9000' >> arrange_lb_test_user.sh
echo 'export GLITE_WMS_LOG_DESTINATION=\$HNAME:9002' >> arrange_lb_test_user.sh
echo export GLITE_LB_SERVER_WPORT=9003 >> arrange_lb_test_user.sh
echo export GLITE_LB_SERVER_PORT=9000 >> arrange_lb_test_user.sh
echo export GLITE_LB_LOGGER_PORT=9002 >> arrange_lb_test_user.sh
echo export GLITE_WMS_LBPROXY_STORE_SOCK=/tmp/lb_proxy_ >> arrange_lb_test_user.sh
echo 'env | egrep "GLITE|\$HNAME|PATH"' >> arrange_lb_test_user.sh
echo pwd >> arrange_lb_test_user.sh
if [ "\$OUTPUT_OPT" == "-i" ]; then
echo echo ======================== >> arrange_lb_test_user.sh
echo echo "  THE CONSOLE IS YOURS" >> arrange_lb_test_user.sh
echo echo ======================== >> arrange_lb_test_user.sh
echo '/bin/bash -i' >> arrange_lb_test_user.sh 
else
echo echo ======================== >> arrange_lb_test_user.sh
echo echo "  REAL TESTS START HERE" >> arrange_lb_test_user.sh
echo echo ======================== >> arrange_lb_test_user.sh
echo 'echo "</verbatim>"' >> arrange_lb_test_user.sh
echo 'echo "<literal>"' >> arrange_lb_test_user.sh
echo sh ./lb-test-permissions.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-event-delivery.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-il-recovery.sh -f /var/glite/log/dglogd.log \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-job-registration.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-https.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-job-states.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-logevent.sh /var/glite/log/dglogd.log \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-notif-recovery.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-notif-msg.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-notif.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-notif-switch.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-notif-stream.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-proxy-delivery.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-ws.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-bdii.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-sandbox-transfer.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-changeacl.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-statistics.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-threaded.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-harvester.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-nagios-probe.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo perl ./lb-test-purge.pl --i-want-to-purge $remotehost:9000 \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo 'echo "</literal>"' >> arrange_lb_test_user.sh
echo 'echo "<verbatim>"' >> arrange_lb_test_user.sh
echo echo ================== >> arrange_lb_test_user.sh
echo echo "  TESTS END HERE" >> arrange_lb_test_user.sh
echo echo ================== >> arrange_lb_test_user.sh
fi
#echo "" >> arrange_lb_test_user.sh

chown \$GLITE_USER:\$GLITE_USER arrange_lb_test_user.sh
chmod +x arrange_lb_test_user.sh

#su -l \$GLITE_USER
su -l \$GLITE_USER --command=/tmp/arrange_lb_test_user.sh
echo "</verbatim>"

EndArrangeScript
}

