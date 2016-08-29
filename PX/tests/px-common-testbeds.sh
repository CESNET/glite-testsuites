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

function gen_arrange_script_px()
{
remotehost=$1
COPYPROXY=$2

INSTALLPKGS='ca-certificates curl globus-proxy-utils wget'
if egrep -iq "Debian|Ubuntu" /etc/issue; then
	INSTALLCMD="aptitude install -y --allow-untrusted"
	# install myproxy too for client utils
	INSTALLPKGS="${INSTALLPKGS} lintian myproxy voms-clients"
else
	if egrep -iq '^Fedora' /etc/redhat-release; then
		VOMSPKG='voms-clients-cpp'
	else
		VOMSPKG='voms-clients'
	fi
	INSTALLCMD="yum install -q -y --nogpgcheck"
	INSTALLPKGS="${INSTALLPKGS} rpmlint ${VOMSPKG}"
fi

cat << EndArrangeScript > arrange_px_test_root.sh 
CERTFILE=\$1
GLITE_USER=\$2
PXTSTCOLS=\$3
OUTPUT_OPT=\$4
GITROOT=git://github.com/CESNET/glite-testsuites.git

echo "Certificate file: \$CERTFILE "
echo "gLite user:       \$GLITE_USER "
echo "Terminal width:   \$PXTSTCOLS "
echo "Output format:    \$OUTPUT_OPT "

export PXTSTCOLS CVSROOT

${INSTALLCMD} ${INSTALLPKGS}

cd /tmp

VCSPATH=\`which git\`

if [ "\$VCSPATH" = "" ]; then
        printf "git binary not present, installing..."
	${INSTALLCMD} git
	echo " done"
fi

glite_id=\`id -u \$GLITE_USER\`

echo \$GLITE_USER user ID is \$glite_id

if [ $COPYPROXY -eq 1 ]; then
	mv \$CERTFILE x509up_u\$glite_id
	chown \$GLITE_USER:\$GLITE_USER x509up_u\${glite_id}
else
	rm -rf /tmp/test-certs/grid-security
	[ -r glite-testsuites/LB/tests/lb-generate-fake-proxy.sh ] || wget -q -P glite-testsuites/LB/tests/ https://raw.github.com/CESNET/glite-testsuites/master/LB/tests/lb-generate-fake-proxy.sh
	chmod +x glite-testsuites/LB/tests/lb-generate-fake-proxy.sh
	FAKE_CAS=\`glite-testsuites/LB/tests/lb-generate-fake-proxy.sh --lsc | grep -E "^X509_CERT_DIR" | sed 's/X509_CERT_DIR=//'\`
	if [ "\$FAKE_CAS" = "" ]; then
                echo "Failed generating proxy" >&2
                exit 2
        else
                cp -rv \$FAKE_CAS/* /etc/grid-security/certificates/
        fi
fi

if [ ! -d /etc/vomses ]; then
        echo Installing experimental VOMS server
        if [ ! -f ./px-voms-install.sh ]; then
                wget https://raw.github.com/CESNET/glite-testsuites/master/PX/tests/px-voms-install.sh
                chmod +x px-voms-install.sh
        fi
        source ./px-voms-install.sh -u glite
else
	printf "Using external voms server:\n===========================\n"
	find /etc/vomses -type f -exec printf "{}: " \; -exec cat {} \;
	printf "===========================\n"

fi


cd /tmp/
 
echo cd > arrange_px_test_user.sh
echo export PXTSTCOLS=\$PXTSTCOLS >> arrange_px_test_user.sh
echo 'export GLITE_MYSQL_ROOT_PASSWORD="[Edited]"' >> arrange_px_test_user.sh
echo mkdir PX_testing >> arrange_px_test_user.sh
echo cd PX_testing >> arrange_px_test_user.sh
echo git clone --depth 1 \$GITROOT >> arrange_px_test_user.sh
echo ls >> arrange_px_test_user.sh
echo cd glite-testsuites/PX/tests >> arrange_px_test_user.sh
echo ulimit -c unlimited >> arrange_px_test_user.sh
echo 'export HNAME=\`hostname -f\`' >> arrange_px_test_user.sh
echo 'env | egrep "GLITE|\$HNAME|PATH"' >> arrange_px_test_user.sh
echo pwd >> arrange_px_test_user.sh
echo id >> arrange_px_test_user.sh
if [ "\$OUTPUT_OPT" = "-i" ]; then
echo echo ======================== >> arrange_px_test_user.sh
echo echo "  THE CONSOLE IS YOURS" >> arrange_px_test_user.sh
echo echo ======================== >> arrange_px_test_user.sh
echo '/bin/bash -i' >> arrange_px_test_user.sh 
else
echo echo ======================== >> arrange_px_test_user.sh
echo echo "  REAL TESTS START HERE" >> arrange_px_test_user.sh
echo echo ======================== >> arrange_px_test_user.sh
echo 'echo "</PRE>"' >> arrange_px_test_user.sh
echo ./px-test-all.sh \$OUTPUT_OPT >> arrange_px_test_user.sh
echo ./px-test-packaging.sh \$OUTPUT_OPT >> arrange_px_test_user.sh
echo ./px-test-build.sh \$OUTPUT_OPT >> arrange_px_test_user.sh
echo 'echo "<PRE>"' >> arrange_px_test_user.sh
echo echo ================== >> arrange_px_test_user.sh
echo echo "  TESTS END HERE" >> arrange_px_test_user.sh
echo echo ================== >> arrange_px_test_user.sh
fi
#echo "" >> arrange_px_test_user.sh

chown \$GLITE_USER:\$GLITE_USER arrange_px_test_user.sh
chmod +x arrange_px_test_user.sh

#su -l \$GLITE_USER -s /bin/sh
su -l \$GLITE_USER -s /bin/sh --command=/tmp/arrange_px_test_user.sh
echo "</PRE>"

EndArrangeScript
}

