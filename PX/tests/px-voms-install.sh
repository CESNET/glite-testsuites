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

function add_voms_user_w_attrs() {
	voms-admin --nousercert --vo vo.org create-user "$1" "$2" "$3" "$4"
	voms-admin --nousercert --vo vo.org set-user-attribute "$1" "$2" attribute1 $RANDOM
	voms-admin --nousercert --vo vo.org set-user-attribute "$1" "$2" attribute2 $RANDOM
	voms-admin --nousercert --vo vo.org add-member Testers "$1" "$2"
}

USERNAME="root"
while test -n "$1"
do
        case "$1" in
                "-u" | "--user") shift; USERNAME="$1" ;;
        esac
        shift
done

egrep -i "Debian|Ubuntu" /etc/issue
if [ $? = 0 ]; then
        INSTALLCMD="apt-get install -q --yes"
	INSTALLPKGS="lintian"
else
        INSTALLCMD="yum install -q -y --nogpgcheck"
	INSTALLPKGS="rpmlint"
fi

${INSTALLCMD} emi-voms-mysql xml-commons-apis wget

#get CAS
if [ ! -f lb-generate-fake-proxy.sh ]; then
	wget -O lb-generate-fake-proxy.sh http://jra1mw.cvs.cern.ch/cgi-bin/jra1mw.cgi/org.glite.testsuites.ctb/LB/tests/lb-generate-fake-proxy.sh?view=co
	chmod +x lb-generate-fake-proxy.sh
fi

FAKE_CAS=`sh ./lb-generate-fake-proxy.sh --lsc | grep -E "^X509_CERT_DIR" | sed 's/X509_CERT_DIR=//'`
if [ "$FAKE_CAS" == "" ]; then
        echo "Failed generating proxy" >&2
        exit 2
else
        cp -rv $FAKE_CAS/* /etc/grid-security/certificates/
fi

service mysqld start

sleep 2

/usr/bin/mysqladmin -u root password [Edited];

mysql --user=root --password=[Edited] -e "grant all on *.* to 'root'@'`hostname`' identified by '[Edited]';"
mysql --user=root --password=[Edited] -e "grant all on *.* to 'root'@'`hostname -f`' identified by '[Edited]';"


cd
mkdir -p yaim/services
cd yaim

cat << EOF > site-info-voms.def
MYSQL_PASSWORD="[Edited]"
SITE_NAME="`hostname -f`"
VOS="vo.org"
BDII_DELETE_DELAY=0
EOF

cat << EOF > services/glite-voms
# VOMS server hostname
VOMS_HOST=`hostname -f`
VOMS_DB_HOST='localhost'

VO_VO_ORG_VOMS_PORT=15000
VO_VO_ORG_VOMS_DB_USER=cert_mysql_user
VO_VO_ORG_VOMS_DB_PASS="[Edited]"
VO_VO_ORG_VOMS_DB_NAME=voms_cert_mysql_db

VOMS_ADMIN_SMTP_HOST=[Edited]
VOMS_ADMIN_MAIL=[Edited]
EOF

sed -i 's/155/255/g' /opt/glite/yaim/examples/edgusers.conf
sed -i 's/156/256/g' /opt/glite/yaim/examples/edgusers.conf

/opt/glite/yaim/bin/yaim -c -s site-info-voms.def -n VOMS

source /etc/profile.d/grid-env.sh

voms-admin --vo vo.org create-attribute-class "attribute1" "The first test attribute" 0
voms-admin --vo vo.org create-attribute-class "attribute2" "The second test attribute" 0
voms-admin --vo vo.org create-attribute-class "attribute3" "The third test attribute" 0

voms-admin --vo vo.org create-group Testers
voms-admin --vo vo.org create-role Tester
voms-admin --vo vo.org set-role-attribute "/vo.org/Testers/" Role=Tester attribute3 "TestAttr$RANDOM"

add_voms_user_w_attrs "/C=UG/L=Tropic/O=Utopia/OU=Relaxation/CN=$USERNAME" "/C=UG/L=Tropic/O=Utopia/OU=Relaxation/CN=the trusted CA" "$USERNAME" "root@`hostname -f`"
add_voms_user_w_attrs "/C=UG/L=Tropic/O=Utopia/OU=Relaxation/CN=$USERNAME client01" "/C=UG/L=Tropic/O=Utopia/OU=Relaxation/CN=the trusted CA" "$USERNAME" "root@`hostname -f`"
add_voms_user_w_attrs "/DC=org/DC=terena/DC=tcs/C=CZ/O=CESNET/CN=Zdenek Sustr 4040" "/C=NL/O=TERENA/CN=TERENA eScience Personal CA" "$USERNAME" "root@`hostname -f`"

mkdir -p /etc/vomses
cat /etc/voms-admin/vo.org/vomses > /etc/vomses/`hostname -f`

echo Experimental VOMS set up with users
voms-admin --vo vo.org list-users

