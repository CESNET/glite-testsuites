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
This script is intended for running a fully automated deployment and functionality test of the C-part of caNl, depending on its examples

Prerequisities:
New empty machine, certificates

Tests called:
	Deployment
	The full caNl-c Test Suite

EndHelpHeader

	echo "Usage: $progname [OPTIONS] hostname"
	echo "Options:"
	echo " -h | --help            Show this help message."
}

STARTTIME=`date +%s`

egrep -i "Debian|Ubuntu" /etc/issue
if [ \$? = 0 ]; then
        INSTALLCMD="apt-get install -q --yes"
        INSTALLPKGS="lintian"
else
        INSTALLCMD="yum install -q -y --nogpgcheck"
        INSTALLPKGS="rpmlint"
fi

$INSTALLCMD wget

# read common definitions and functions
for COMMON in canl-common.sh test-common.sh canl-common-testbeds.sh
do
	if [ ! -r ${COMMON} ]; then
		printf "Downloading common definitions '${COMMON}'"
		wget -O ${COMMON} http://jra1mw.cvs.cern.ch/cgi-bin/jra1mw.cgi/org.glite.testsuites.ctb/CANL-C/tests/$COMMON?view=co > /dev/null
		if [ ! -r ${COMMON} ]; then
			exit 2
		else 
			chmod +x $COMMON
			test_done
		fi
	fi
done
source canl-common.sh
source canl-common-testbeds.sh
#also read L&B common definitions for common functions.
if [ ! -r lb-common-testbeds.sh ]; then
	printf "Downloading common definitions 'lb-common-testbeds.sh'"
        wget -O lb-common-testbeds.sh http://jra1mw.cvs.cern.ch/cgi-bin/jra1mw.cgi/org.glite.testsuites.ctb/LB/tests/lb-common-testbeds.sh?view=co > /dev/null
        if [ ! -r lb-common-testbeds.sh ]; then
                exit 2
        else
		chmod +x lb-common-testbeds.sh
                test_done
        fi
fi
source lb-common-testbeds.sh


printf "Getting the 'install' script... "
# Example script, for real tests it should be downloaded or otherwise obtained
SCENARIO=${SCENARIO:-"Clean installation"}
test -s caNlInstall.sh || cat << EndInstallScript > caNlInstall.sh
rpm -Uvhi http://dl.fedoraproject.org/pub/epel/5/x86_64/epel-release-5-4.noarch.rpm
yum install -y yum-priorities yum-protectbase

cd /etc/yum.repos.d
wget --no-check-certificate https://twiki.cern.ch/twiki/pub/EMI/EMI-2/emi-2-rc3-sl5.repo

yum install -y canl-c
EndInstallScript
test_done


printf "Generating the 'arrange' script... "
gen_arrange_script_canl `hostname -f` 0
test_done


printf "Installing... "
sh caNlInstall.sh > Install_log.txt 2> Install_err.log
test_done

printf "Running tests... "
sh arrange_canl_test_root.sh none glite 80 '-x' > test_log.txt 2> test_err.log
test_done

ENDTIME=`date +%s`

#Generating report section
gen_deployment_header $ENDTIME $STARTTIME "$SCENARIO" > report.twiki

cat caNlInstall.sh >> report.twiki
printf "</verbatim>

---++++ Full Output of the Installation

<verbatim>\n" >> report.twiki
cat Install_log.txt >> report.twiki

printf "</verbatim>

---+++ Tests

| !TestPlan | <B>N/A</B> |
| Tests | http://jra1mw.cvs.cern.ch/cgi-bin/jra1mw.cgi/org.glite.testsuites.ctb/CANL-C/tests/ |

<verbatim>\n" >> report.twiki
cat test_log.txt >> report.twiki

#Generating test report

PRODUCT="emi.canl.c"
UNITESTEXEC="NO"
REMARKS="No unit tests implemented"
PERFORMANCEEXEC="NO"
TESTREPOCONTENTS="`cat ./repo_packages.txt`"
PRODREPOCONTENTS="`cat ./prod_packages.txt`"
INSTALLCOMMAND="`cat GridSiteInstall.sh`"
INSTALLLOG="`cat Install_log.txt`"
CONFIGLOG="caNl does not use any specific configuration procedure. No log provided"
#UPGRADECMD
UNITTESTURL="NA"
TESTPLANURL="http://jra1mw.cvs.cern.ch/cgi-bin/jra1mw.cgi/org.glite.testsuites.ctb/CANL-C/tests/"
FUNCTIONALITYTESTURL="https://twiki.cern.ch/twiki/bin/view/EMI/EMIcaNl#Certification_Test_Results"

gen_test_report > TestRep.txt

