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
	echo " -r | --repo            Add repository contents to main report"
}

add_repos=0
while test -n "$1"
do
        case "$1" in
                "-h" | "--help") showHelp && exit 2 ;;
                "-r" | "--repos") add_repos=1 ;;
        esac
        shift
done

STARTTIME=`date +%s`
REPORT=report.html

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

$INSTALLCMD wget ca-certificates

# read common definitions and functions
for COMMON in gridsite-common.sh gridsite-common-testbeds.sh
do
	if [ ! -r ${COMMON} ]; then
		printf "Downloading common definitions '${COMMON}'"
		wget -q https://raw.github.com/CESNET/glite-testsuites/master/gridsite/tests/$COMMON
		if [ ! -r ${COMMON} ]; then
			exit 2
		else 
			echo " done"
		fi
	fi
done
#also read L&B common definitions for common functions.
for COMMON in test-common.sh lb-common-testbeds.sh
do
	if [ ! -r ${COMMON} ]; then
		if [ -r `dirname $0`/../../LB/tests/${COMMON} ]; then
			printf "Creating symbolic link for '${COMMON}'"
			ln -s ../../LB/tests/${COMMON} .
			echo " done"
		else
			printf "Downloading common definitions '${COMMON}'"
			wget -q https://raw.github.com/CESNET/glite-testsuites/master/LB/tests/$COMMON
			if [ ! -r ${COMMON} ]; then
				exit 2
			else
				echo " done"
			fi
		fi
	fi
done
source gridsite-common.sh
source gridsite-common-testbeds.sh
source lb-common-testbeds.sh


printf "Getting the 'install' script... "
# Example script, for real tests it should be downloaded or otherwise obtained
SCENARIO=${SCENARIO:-"Clean installation"}
test -s GridSiteInstall.sh || cat << EndInstallScript > GridSiteInstall.sh
#CATEGORY=EMI2-RELEASE
#PRETEST="wget --no-check-certificate -O /tmp/test http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-7.noarch.rpm && wget --no-check-certificate -O /tmp/test http://emisoft.web.cern.ch/emisoft/dist/EMI/2/sl6/x86_64/base/emi-release-2.0.0-1.sl6.noarch.rpm && wget --no-check-certificate -O /tmp/test http://etics-repository.cern.ch/repository/pm/registered/repomd/id/c1dd37c2-c249-4477-a81e-5e1a7abcf2d5/sl6_x86_64_gcc446EPEL/etics-registered-build-by-id-protect.repo"
#COMPONENT=gridsite
#SCENARIO="Clean installation"
rpm -ivh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-7.noarch.rpm
yum install -y yum-priorities yum-protectbase
rpm -ivh http://emisoft.web.cern.ch/emisoft/dist/EMI/2/sl6/x86_64/base/emi-release-2.0.0-1.sl6.noarch.rpm
cd /etc/yum.repos.d
wget http://etics-repository.cern.ch/repository/pm/registered/repomd/id/c1dd37c2-c249-4477-a81e-5e1a7abcf2d5/sl6_x86_64_gcc446EPEL/etics-registered-build-by-id-protect.repo
echo priority=39 >> etics-registered-build-by-id-protect.repo
echo timeout=120 >> etics-registered-build-by-id-protect.repo
cd

yum install --nogpgcheck -y gridsite gridsite-commands gridsite-debuginfo gridsite-devel gridsite-gsexec gridsite-service-clients gridsite-services

#
# example how to use external VOMS server tests
# (deployed localy by default)
#
mkdir /etc/vomses
echo '"vo.org" "emicert-voms.civ.zcu.cz" "15000" "/DC=org/DC=terena/DC=tcs/C=CZ/O=University of West Bohemia/CN=emicert-voms.civ.zcu.cz" "vo.org"' > /etc/vomses/emicert-voms.civ.zcu.cz
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
gen_deployment_header $ENDTIME $STARTTIME "$SCENARIO" > $REPORT

if [ $add_repos -eq 1 ]; then
	echo "$SCENARIO" | grep -E -i "upgrade|update" > /dev/null
	if [ $? -eq 0 ]; then
		printf "
<A NAME=\"${ID}-ProdRepo\"></A><H4>Production Repo Contents</H4>

<PRE>\n" >> $REPORT
		htmlcat ./prod_packages.txt >> $REPORT
		printf "</PRE>\n" >> $REPORT
	fi

	printf "
<A NAME=\"${ID}-TestRepo\"></A><H4>Test Repo Contents</H4>

<PRE>\n" >> $REPORT
	htmlcat ./repo_packages.txt >> $REPORT
	printf "</PRE>\n" >> $REPORT
fi

printf "
<A NAME=\"${ID}-Process\"></A><H4>Process</H4>

<PRE>\n" >> $REPORT

htmlcat GridSiteInstall.sh >> $REPORT
printf "</PRE>

<A NAME=\"${ID}-Output\"></A><H4>Full Output of the Installation</H4>

<PRE>\n" >> $REPORT
htmlcat Install_log.txt >> $REPORT

printf "</PRE>

<A NAME=\"${ID}-Tests\"></A><H3>Tests</H3>

<table>
<tr><td> TestPlan </td><td> <A HREF=\"https://twiki.cern.ch/twiki/bin/view/EGEE/GridSiteTestPlan\">https://twiki.cern.ch/twiki/bin/view/EGEE/GridSiteTestPlan</A> </td></tr>
<tr><td> Tests </td><td> <A HREF=\"https://github.com/CESNET/glite-testsuites/tree/master/gridsite/tests/\">https://github.com/CESNET/glite-testsuites/tree/master/gridsite/tests/</A> </td></tr>
</table>

<PRE>\n" >> $REPORT
cat test_log.txt >> $REPORT

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
TESTPLANURL="https://github.com/CESNET/glite-testsuites/tree/master/gridsite/tests/"
FUNCTIONALITYTESTURL="https://twiki.cern.ch/twiki/bin/view/EGEE/SA3Testing#GridSite"

gen_test_report > TestRep.txt

