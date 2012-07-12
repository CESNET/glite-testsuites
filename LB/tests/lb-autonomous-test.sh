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
This script is intended for running a fully automated deployment and functionality test of an L&B server

Prerequisities:
New empty machine, certificates

Tests called:
	Deployment
	The full L&B Functional Test Suite

EndHelpHeader

	echo "Usage: $progname [OPTIONS] hostname"
	echo "Options:"
	echo " -h | --help            Show this help message."
}

egrep -i "Debian|Ubuntu" /etc/issue
if [ $? = 0 ]; then
        INSTALLCMD="apt-get install -q --yes"
        INSTALLPKGS="lintian"
else
        INSTALLCMD="yum install -q -y --nogpgcheck"
        INSTALLPKGS="rpmlint"
fi

$INSTALLCMD wget

# read common definitions and functions
for COMMON in lb-common.sh test-common.sh lb-common-testbeds.sh
do
	if [ ! -r ${COMMON} ]; then
		printf "Downloading common definitions '${COMMON}'"
		wget -O ${COMMON} http://jra1mw.cvs.cern.ch/cgi-bin/jra1mw.cgi/org.glite.testsuites.ctb/LB/tests/$COMMON?view=co > /dev/null
		if [ ! -r ${COMMON} ]; then
			exit 2
		else 
			test_done
		fi
	fi
done
source lb-common.sh
source lb-common-testbeds.sh

STARTTIME=`date +%s`

printf "Getting the 'install' script... "
# Example script, for real tests it should be downloaded or otherwise obtained
SCENARIO=${SCENARIO:-"Clean installation"}
test -s LBinstall.sh || cat << EndInstallScript > LBinstall.sh 
rpm -ivh http://dl.fedoraproject.org/pub/epel/5/x86_64/epel-release-5-4.noarch.rpm
yum install -y yum-priorities yum-protectbase
rpm -i http://emisoft.web.cern.ch/emisoft/dist/EMI/1/sl5/x86_64/base/emi-release-1.0.0-1.sl5.noarch.rpm



yum install -y --nogpgcheck emi-lb
yum install -y --nogpgcheck emi-lb-nagios-plugins

cd ~/
mkdir -m 700 yaim
cd yaim

cat << EOF > site-info.def
MYSQL_PASSWORD=[Edited]
SITE_NAME=delwin
SITE_EMAIL="[Edited]"
GLITE_LB_TYPE=both
GLITE_LB_SUPER_USERS="/C=UG/L=Tropic/O=Utopia/OU=Relaxation/CN=glite"
EOF

sed -i 's/155/255/g' /opt/glite/yaim/examples/edgusers.conf

/opt/glite/yaim/bin/yaim -c -s ./site-info.def -n glite-LB
EndInstallScript
test_done


printf "Generating the 'arrange' script... "
gen_arrange_script `hostname -f` 0
test_done


printf "Installing... "
sh LBinstall.sh > Install_log.txt 2> Install_err.log
test_done

printf "Running tests... "
sh arrange_lb_test_root.sh none glite 80 '-x' > test_log.txt 2> test_err.log
test_done

printf "Collecting package list... "
gen_repo_lists ./prod_packages.txt ./repo_packages.txt
test_done

ENDTIME=`date +%s`

#Generating report section
gen_deployment_header $ENDTIME $STARTTIME "$SCENARIO" > report.twiki

echo "$SCENARIO" | grep -E -i "upgrade|update" > /dev/null
if [ $? -eq 0 ]; then
        printf "\n---++++ Production Repo Contents

<verbatim>\n" >> report.twiki
        cat ./prod_packages.txt >> report.twiki
        printf "</verbatim>\n" >> report.twiki
fi

printf "\n---++++ Test Repo Contents

<verbatim>\n" >> report.twiki
cat ./repo_packages.txt >> report.twiki
printf "</verbatim>

---++++ Process

<verbatim>\n" >> report.twiki


cat LBinstall.sh >> report.twiki
printf "</verbatim>

---++++ Full Output of the Installation

<verbatim>\n" >> report.twiki
cat Install_log.txt >> report.twiki

printf "</verbatim>

---+++ Tests

| <literal>TestPlan</literal> | https://twiki.cern.ch/twiki/bin/view/EGEE/LBTestPlan |
| <literal>TestPlan</literal> Tests | http://glite.cvs.cern.ch/cgi-bin/glite.cgi/org.glite.testsuites.ctb/LB/tests/ |
| <literal>TestPlan</literal> Test Documentation | http://egee.cesnet.cz/cvsweb/LB/LBTP.pdf |

<verbatim>\n" >> report.twiki
cat test_log.txt >> report.twiki

PRODUCT="emi.lb"
UNITESTEXEC="YES"
REMARKS=""
PERFORMANCEEXEC="YES"
TESTREPOCONTENTS="`cat ./repo_packages.txt`"
PRODREPOCONTENTS="`cat ./prod_packages.txt`"
echo "$SCENARIO" | grep -E -i "upgrade|update" > /dev/null
if [ $? != 0 ]; then
	INSTALLCOMMAND="`cat LBinstall.sh`"
	UPGRADECMD=""
else
	INSTALCOMMAND="# Copy here initial part of Upgrade Command
"
	UPGRADECMD="`cat LBinstall.sh`"
fi
INSTALLLOG="`cat Install_log.txt`"
CONFIGLOG="Configuration log shown with the installation log, see directly above."
UNITTESTURL="See Build Report. Unit tests are an integral part of the build."
TESTPLANURL="http://jra1mw.cvs.cern.ch/cgi-bin/jra1mw.cgi/org.glite.testsuites.ctb/LB/tests/"
FUNCTIONALITYTESTURL="https://twiki.cern.ch/twiki/bin/view/EGEE/SA3Testing#LB"

gen_test_report > TestRep.txt


