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
This script is intended for running a fully automated deployment and functionality test of a Web server with gridsite extensions

Prerequisities:
New empty machine, certificates

Tests called:
	Deployment
	The full GridSite Functional Test Suite

EndHelpHeader

	echo "Usage: $progname [OPTIONS] hostname"
	echo "Options:"
	echo " -h | --help            Show this help message."
}

STARTTIME=`date +%s`

egrep -i "Debian|Ubuntu" /etc/issue
if [ $? = 0 ]; then
        INSTALLCMD="apt-get install -q --yes"
        INSTALLPKGS="lintian"
	UPGRADECMD="apt-get upgrade"
else
        INSTALLCMD="yum install -q -y --nogpgcheck"
        INSTALLPKGS="rpmlint"
	UPGRADECMD="yum update"
fi

$INSTALLCMD wget

# read common definitions and functions
for COMMON in gridsite-common.sh test-common.sh gridsite-common-testbeds.sh
do
	if [ ! -r ${COMMON} ]; then
		printf "Downloading common definitions '${COMMON}'"
		wget -O ${COMMON} http://jra1mw.cvs.cern.ch/cgi-bin/jra1mw.cgi/org.glite.testsuites.ctb/gridsite/tests/$COMMON?view=co > /dev/null
		if [ ! -r ${COMMON} ]; then
			exit 2
		else 
			chmod +x $COMMON
			test_done
		fi
	fi
done
source gridsite-common.sh
source gridsite-common-testbeds.sh
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
test -s GridSiteInstall.sh || cat << EndInstallScript > GridSiteInstall.sh
rpm -Uvhi http://dl.fedoraproject.org/pub/epel/5/x86_64/epel-release-5-4.noarch.rpm
yum install -y yum-priorities yum-protectbase
rpm -i http://emisoft.web.cern.ch/emisoft/dist/EMI/1/sl5/x86_64/base/emi-release-1.0.0-1.sl5.noarch.rpm

#cd /etc/yum.repos.d/
#wget http://etics-repository.cern.ch/repository/pm/registered/repomd/id/2efadb29-61fb-4d5f-be8f-17b799a269e0/sl5_x86_64_gcc412EPEL/etics-registered-build-by-id-protect.repo
#echo priority=45 >> etics-registered-build-by-id-protect.repo

yum install -y gridsite-apache gridsite-commands gridsite-debuginfo gridsite-devel.x86_64 gridsite-gsexec gridsite-service-clients gridsite-services gridsite-shared
EndInstallScript
test_done


printf "Generating the 'arrange' script... "
gen_arrange_script_gridsite `hostname -f` 0
test_done


printf "Installing... "
sh GridSiteInstall.sh > Install_log.txt 2> Install_err.log && test_done || test_failed

printf "Running tests... "
sh arrange_gridsite_test_root.sh none glite 80 '-x' > test_log.txt 2> test_err.log && test_done || test_failed

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

cat GridSiteInstall.sh >> report.twiki
printf "</verbatim>

---++++ Full Output of the Installation

<verbatim>\n" >> report.twiki
cat Install_log.txt >> report.twiki

printf "</verbatim>

---+++ Tests

| !TestPlan | https://twiki.cern.ch/twiki/bin/view/EGEE/GridSiteTestPlan |
| Tests | http://jra1mw.cvs.cern.ch/cgi-bin/jra1mw.cgi/org.glite.testsuites.ctb/gridsite/tests/ |

<verbatim>\n" >> report.twiki
cat test_log.txt >> report.twiki

#Generating test report

PRODUCT="emi.gridsite"
UNITESTEXEC="NO"
REMARKS="No unit tests implemented"
PERFORMANCEEXEC="NO"
TESTREPOCONTENTS="`cat ./repo_packages.txt`"
PRODREPOCONTENTS="`cat ./prod_packages.txt`"
INSTALLCOMMAND="`cat GridSiteInstall.sh`"
INSTALLLOG="`cat Install_log.txt`"
CONFIGLOG="GridSite does not use any specific configuration procedure. No log provided"
#UPGRADECMD
UNITTESTURL="NA"
TESTPLANURL="http://jra1mw.cvs.cern.ch/cgi-bin/jra1mw.cgi/org.glite.testsuites.ctb/gridsite/tests/"
FUNCTIONALITYTESTURL="https://twiki.cern.ch/twiki/bin/view/EGEE/SA3Testing#GridSite"

gen_test_report > TestRep.txt

