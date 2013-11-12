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

function gen_arrange_script_canl()
{
remotehost=$1
COPYPROXY=$2

egrep -i "Debian|Ubuntu" /etc/issue
if [ $? = 0 ]; then 
	INSTALLCMD="apt-get install -q --yes --force-yes"
	INSTALLPKGS="lintian"
else
	INSTALLCMD="yum install -q -y --nogpgcheck"
	INSTALLPKGS="rpmlint"
fi

cat << EndArrangeScript > arrange_canl_test_root.sh 
CERTFILE=\$1
GLITE_USER=\$2
GSTSTCOLS=\$3
OUTPUT_OPT=\$4
GITROOT=git://github.com/CESNET/glite-testsuites.git

echo "Certificate file: \$CERTFILE "
echo "gLite user:       \$GLITE_USER "
echo "Terminal width:   \$GSTSTCOLS "
echo "Output format:    \$OUTPUT_OPT "

export GSTSTCOLS CVSROOT

${INSTALLCMD} wget ca-certificates lsof git voms-clients globus-proxy-utils $INSTALLPKGS

cd /tmp

if [ $COPYPROXY -eq 1 ]; then
	mv \$CERTFILE x509up_u\`id -u\`
	chown \`id -un\`:\`id -gn\` x509up_u\`id -u\`
else
	rm -rf /tmp/test-certs/grid-security
	[ -r glite-testsuites/LB/tests/lb-generate-fake-proxy.sh ] || wget -q -P glite-testsuites/LB/tests/ https://raw.github.com/CESNET/glite-testsuites/master/LB/tests/lb-generate-fake-proxy.sh
	chmod +x glite-testsuites/LB/tests/lb-generate-fake-proxy.sh
	glite-testsuites/LB/tests/lb-generate-fake-proxy.sh --all > fake-prox.out.\$\$
	FAKE_CAS=\`cat fake-prox.out.\$\$ | grep -E "^X509_CERT_DIR" | sed 's/X509_CERT_DIR=//'\`
	if [ "\$FAKE_CAS" = "" ]; then
                echo "Failed generating proxy" >&2
                exit 2
        else
                cp -rv \$FAKE_CAS/* /etc/grid-security/certificates/
        fi

	TRUSTED_CERTS=\`cat fake-prox.out.\$\$ | grep -E "^TRUSTED_CERTS" | sed 's/TRUSTED_CERTS=//'\`
	export X509_USER_CERT=\${TRUSTED_CERTS}/trusted_client00.cert
	export X509_USER_KEY=\${TRUSTED_CERTS}/trusted_client00.priv-clear
	rm fake-prox.out.\$\$
fi

cd ~/
mkdir caNl_testing
cd caNl_testing
git clone --depth 0 \$GITROOT
cd glite-testsuites/CANL-C/tests
echo ========================
echo "  REAL TESTS START HERE"
echo ========================
echo "</PRE>"
echo "<literal>"
./canl-test-cert-handle.sh --origin \$X509_USER_CERT --key \$X509_USER_KEY \$OUTPUT_OPT
./canl-test-cs-openssl.sh \$OUTPUT_OPT
./canl-test-sec-connection.sh \$OUTPUT_OPT
./canl-test-sha2.sh \$OUTPUT_OPT
./canl-test-packaging.sh \$OUTPUT_OPT
./canl-test-build.sh \$OUTPUT_OPT
echo "</literal>"
echo "<PRE>"
echo ==================
echo "  TESTS END HERE"
echo ==================
echo "</PRE>"

EndArrangeScript
}

