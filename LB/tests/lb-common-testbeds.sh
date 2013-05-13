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

egrep -i "Debian|Ubuntu" /etc/issue
if [ $? = 0 ]; then
	INSTALLCMD="aptitude install -y --allow-untrusted"
	INSTALLPKGS="lintian"
else
	INSTALLCMD="yum install -q -y --nogpgcheck"
	INSTALLPKGS="rpmlint postgresql-server"
fi

cat << EndArrangeScript > arrange_lb_test_root.sh 
CERTFILE=\$1
GLITE_USER=\$2
LBTSTCOLS=\$3
OUTPUT_OPT=\$4
GITROOT=git://github.com/CESNET/glite-testsuites.git

echo "Certificate file: \$CERTFILE "
echo "gLite user:       \$GLITE_USER "
echo "Terminal width:   \$LBTSTCOLS "
echo "Output format:    \$OUTPUT_OPT "

export LBTSTCOLS CVSROOT

${INSTALLCMD} globus-proxy-utils postgresql voms-clients curl wget ca-certificates sudo bc $INSTALLPKGS

/etc/init.d/postgresql initdb >/dev/null 2>&1
/etc/init.d/postgresql start
sleep 10
for conf in /etc/postgresql/8.4/main/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf; do
	if [ -f \$conf ]; then
		break;
	fi
done
mv \$conf \$conf.orig
cat >\$conf <<EOF
local all all trust
host all all 127.0.0.1/32 ident
host all all ::1/128 ident
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
	FAKE_CAS=\`glite-testsuites/LB/tests/lb-generate-fake-proxy.sh | grep -E "^X509_CERT_DIR" | sed 's/X509_CERT_DIR=//'\`
	if [ "\$FAKE_CAS" = "" ]; then
                echo "Failed generating proxy" >&2
                exit 2
        else
                cp -rv \$FAKE_CAS/* /etc/grid-security/certificates/
        fi
fi

#Allow glite user to read certain system files. Talk about dirty hacks.
grep -E "\$GLITE_USER.*/bin/cat" /etc/sudoers > /dev/null 2> /dev/null
if [ ! \$? = 0 ]; then
	printf "\n\$GLITE_USER\tALL=NOPASSWD: /bin/cat /etc/cron.d/glite-lb-purge.cron,/bin/cat /var/log/messages\n\n" >> /etc/sudoers
fi
sed -i 's/^Defaults[ \t]*requiretty/#Defaults\trequiretty/' /etc/sudoers
visudo -c

echo cd > arrange_lb_test_user.sh
echo export LBTSTCOLS=\$LBTSTCOLS >> arrange_lb_test_user.sh
echo 'export GLITE_MYSQL_ROOT_PASSWORD="[Edited]"' >> arrange_lb_test_user.sh
echo mkdir -p LB_testing >> arrange_lb_test_user.sh
echo cd LB_testing >> arrange_lb_test_user.sh
echo git clone --depth 0 \$GITROOT >> arrange_lb_test_user.sh
echo ls >> arrange_lb_test_user.sh
echo cd glite-testsuites/LB/tests >> arrange_lb_test_user.sh
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
echo id >> arrange_lb_test_user.sh
if [ "\$OUTPUT_OPT" = "-i" ]; then
echo echo ======================== >> arrange_lb_test_user.sh
echo echo "  THE CONSOLE IS YOURS" >> arrange_lb_test_user.sh
echo echo ======================== >> arrange_lb_test_user.sh
echo '/bin/bash -i' >> arrange_lb_test_user.sh 
else
echo echo ======================== >> arrange_lb_test_user.sh
echo echo "  REAL TESTS START HERE" >> arrange_lb_test_user.sh
echo echo ======================== >> arrange_lb_test_user.sh
echo 'echo "</PRE>"' >> arrange_lb_test_user.sh
echo 'echo "<literal>"' >> arrange_lb_test_user.sh
echo 'log_fprefix=/var/spool/glite/lb-locallogger' >> arrange_lb_test_user.sh
echo 'if [ ! -d \$log_fprefix ]; then log_fprefix=/var/glite/log; fi' >> arrange_lb_test_user.sh
echo 'log_fprefix=\$log_fprefix/dglogd.log' >> arrange_lb_test_user.sh
echo ./lb-test-permissions.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-event-delivery.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-il-recovery.sh -f '\$log_fprefix' \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-job-registration.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-https.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-job-states.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-logevent.sh '\$log_fprefix' \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-collections.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-notif-recovery.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-notif-msg.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-notif.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-notif-switch.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-notif-stream.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-notif-keeper.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-proxy-delivery.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-ws.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-bdii.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-sandbox-transfer.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-changeacl.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-statistics.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-threaded.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-harvester.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-nagios-probe.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-packaging.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo ./lb-test-dump-load.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo perl ./lb-test-purge.pl --i-want-to-purge $remotehost:9000 \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo 'echo "</literal>"' >> arrange_lb_test_user.sh
echo 'echo "<PRE>"' >> arrange_lb_test_user.sh
echo echo ================== >> arrange_lb_test_user.sh
echo echo "  TESTS END HERE" >> arrange_lb_test_user.sh
echo echo ================== >> arrange_lb_test_user.sh
fi
#echo "" >> arrange_lb_test_user.sh

chown \$GLITE_USER:\$GLITE_USER arrange_lb_test_user.sh
chmod +x arrange_lb_test_user.sh

#su -l \$GLITE_USER
su -l \$GLITE_USER --command=/tmp/arrange_lb_test_user.sh
echo "</PRE>"

EndArrangeScript
}

function gen_deployment_header()
{
DURATION=`expr $1 - $2`
SCENARIO="$3"

ISSUE=`cat /etc/issue | head -n 1 | sed -r 's/\s*(release|\\\\).*$//'`
PLATFORM=`uname -i`
if [ "$PLATFORM" == "unknown" ]; then
    PLATFORM="`uname -sr`"
fi
TESTBED=`hostname -f`
DISTRO=`cat /etc/issue | head -n 1 | sed 's/\s.*$//'`
VERSION=`cat /etc/issue | head -n 1 | grep -E -o "[0-9]+(\.[0-9]+)?"`
MAJOR=`echo $VERSION | sed 's/\..*$//'`

printf "
<H2>$SCENARIO, $DISTRO $MAJOR ($PLATFORM)</H2>

<H3>Environment</H3>
#CleanInstallation

Clean installation according to EMI guidelines (CA certificates, proxy certificate...).

<table>
<tr><td> OS Issue </td><td> $ISSUE </td></tr>
<tr><td> Platform </td><td> $PLATFORM </td></tr>
<tr><td> Host </td><td> =$TESTBED= </td></tr>
<tr><td> Duration </td><td> `expr $DURATION / 60` min </td></tr>
<tr><td> Testbed uptime </td><td> =`uptime | sed 's/^\s*//'`= </td></tr>
</table>

"
}

function gen_repo_lists()
{
	egrep -i "Debian|Ubuntu" /etc/issue
	if [ $? = 0 ]; then
		apt-cache showpkg `apt-cache pkgnames` | awk '\
			/^Package:/ { pkg=$2; }
			/^Versions:/ {
				getline
			        print pkg, $0
			}
			/.*/ { next }' | sed 's/[()]//g' > /tmp/allpkgs.$$.txt

		#
		# rough distinguish between PROD and TEST repo on Debian
		#   1) filtering by name
		#   2) OS vs non-OS packages
		#
		#cat /tmp/allpkgs.$$.txt | cut -f3- -d' ' | sed 's/ /\n/g' | sort | uniq > /tmp/allrepos.$$.txt
		cat /tmp/allpkgs.$$.txt | grep -Ei '\<(lib)?(glite|emi|canl|gridsite|voms|myproxy|globus)' | grep -Ev '(^emil |canlock)' > /tmp/somepkgs.$$.txt
		cat /tmp/somepkgs.$$.txt | grep -E 'debian.*(sid|wheezy|squeeze)' > $1
		cat /tmp/somepkgs.$$.txt | grep -v -E 'debian.*(sid|wheezy|squeeze)' > $2
	else
		yum install -y -q yum-utils
		repoquery -a --qf "%{name} %{version} %{repoid}" > /tmp/allpkgs.$$.txt
		repoquery -a --qf "%{repoid}" | sort | uniq > /tmp/allrepos.$$.txt

		grep -i etics /tmp/allrepos.$$.txt > /dev/null
		if [ $? = 0 ]; then
			PRODREPO="EMI"
			TESTREPO="ETICS"
		else
			printf " etics repo not found, trying to distinguish between EMI repos "
			PRODREPO=`cat /tmp/allrepos.$$.txt | grep -o -E "EMI-[0-9]+" | sort | uniq | head -n 1`
			TESTREPO=`cat /tmp/allrepos.$$.txt | grep -o -E "EMI-[0-9]+" | sort | uniq | tail -n 1`
		fi

		cat /tmp/allpkgs.$$.txt | grep " $PRODREPO" > $1
		cat /tmp/allpkgs.$$.txt | grep " $TESTREPO" > $2
	fi

	rm -f /tmp/allpkgs.$$.txt /tmp/allrepos.$$.txt /tmp/somepkgs.$$.txt
}

function gen_test_report()
{
cat <<EOF
*********************************
EMI Test Report Template 
*********************************

- Product: $PRODUCT

- Release Task:

- ETICS Subsystem Configuration Name:

- VCS Tag:

- EMI Major Release:

- Platforms:

- Author: 

- Date:

- Test Report Template : v. 3.2

*************
Summary 
*************

1. Deployment tests: 
   1.1. Clean Installation - PASS
   1.2. Upgrade Installation - PASS
2. Static Code Analysis - NA
3. Unit Tests Execution - $UNITESTEXEC
4. System tests:
  4.1. Functionality tests - PASS
  4.2. Regression tests - PASS
  4.3. Standard Conformance tests - NA
  4.4. Performance tests - $PERFORMANCEEXEC
  4.5. Scalability tests - NA
  4.6. Integration tests - NA

REMARKS:

*************************** Detailed Testing Report ***************************************

1. Deployment log 
************************

1.1. Clean Installation
-----------------------------
- YUM/APT Testing Repo file contents:

$TESTREPOCONTENTS

- YUM/APT Install command:

$INSTALLCOMMAND

- YUM/APT log:

$INSTALLLOG

- Configuration log:

$CONFIGLOG

1.2. Upgrade Installation
--------------------------------
- YUM/APT Production Repo file contents:

$PRODREPOCONTENTS

- YUM/APT Install command:

$INSTALLCOMMAND

- YUM/APT Testing Repo file contents:

$TESTREPOCONTENTS

- YUM/APT Upgrade command:

$UPGRADECMD

- YUM/APT log:

$INSTALLLOG

- Configuration log:

$CONFIGLOG

2. Static Code Analysis
******************************
- URL where static code analysis results can be accessed

N/A

3. Unit Tests
*****************
- URL pointing to the results of the Unit Tests.

$UNITTESTURL

- Code Coverage %, if available.

N/A

4. System tests 
*********************
- URL where the tests/testsuite can be accessed:

$TESTPLANURL

- URL where the test results can be accessed:

$FUNCTIONALITYTESTURL
EOF
}
