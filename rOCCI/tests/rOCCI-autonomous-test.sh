#!/bin/bash
#The work represented by this source file is partially or entirely funded
#by the EGI-InSPIRE project through the European Commission's 7th Framework
#Programme (contract # INFSO-RI-261323)
#
#Copyright (c) 2014 CESNET
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#http://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.

# show help and usage
progname=`basename $0`
showHelp()
{
cat << EndHelpHeader
This script is intended for running a fully automated deployment and functionality test of the rOCCI Framework

Prerequisities:
New empty machine

Tests called:
	Deployment
	The rOCCI Test Suite

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
else
        INSTALLCMD="yum install -q -y --nogpgcheck"
        INSTALLPKGS="rpmlint"
fi

$INSTALLCMD wget ca-certificates

# read common definitions and functions
for COMMON in rOCCI-common.sh rOCCI-common-testbeds.sh
do
	if [ ! -r ${COMMON} ]; then
		printf "Downloading common definitions '${COMMON}'"
		wget -q https://raw.github.com/sustr4/glite-testsuites/master/rOCCI/tests/$COMMON
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
source rOCCI-common.sh
source rOCCI-common-testbeds.sh
source lb-common-testbeds.sh


printf "Getting the 'install' script... "
# Example script, for real tests it should be downloaded or otherwise obtained
SCENARIO=${SCENARIO:-"Clean installation"}
test -s rOCCIInstall.sh || cat << EndInstallScript > rOCCIInstall.sh
rpm -ivh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
yum install -y yum-priorities yum-protectbase

cd /etc/yum.repos.d
wget http://repository.egi.eu/community/software/rocci.cli/4.2.x/releases/repofiles/sl-6-x86_64.repo

yum install -y occi-cli
EndInstallScript
test_done


printf "Generating the 'arrange' script... "
gen_arrange_script_rOCCI `hostname -f` 0
test_done


printf "Installing... "
sh rOCCIInstall.sh > Install_log.txt 2> Install_err.log && test_done || test_failed

printf "Running tests... "
sh arrange_rOCCI_test_root.sh none glite 80 '-x' > test_log.txt 2> test_err.log && test_done || test_failed

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
htmlcat rOCCIInstall.sh >> $REPORT
printf "</PRE>

<A NAME=\"${ID}-Output\"></A><H4>Full Output of the Installation</H4>

<PRE>\n" >> $REPORT
htmlcat Install_log.txt >> $REPORT

printf "</PRE>

<A NAME=\"${ID}-Tests\"></A><H3>Tests</H3>

<table>
<tr><td> TestPlan </td><td> <B>N/A</B> </td></tr>
<tr><td> Tests </td><td> <A HREF=\"https://github.com/CESNET/glite-testsuites/tree/master/rOCCI/tests/\">https://github.com/CESNET/glite-testsuites/tree/master/rOCCI/tests/</A> </td></tr>
</table>

<PRE>\n" >> $REPORT
cat test_log.txt >> $REPORT

#Generating test report

PRODUCT="rOCCI"
UNITESTEXEC="YES"
REMARKS="Kick-ass unit tests, all passed"
PERFORMANCEEXEC="NO"
TESTREPOCONTENTS="`cat ./repo_packages.txt`"
PRODREPOCONTENTS="`cat ./prod_packages.txt`"
INSTALLCOMMAND="`cat rOCCIInstall.sh`"
INSTALLLOG="`cat Install_log.txt`"
CONFIGLOG="rOCCI does not use any specific configuration procedure. No log provided"
#UPGRADECMD
UNITTESTURL="NA"
TESTPLANURL="https://github.com/CESNET/glite-testsuites/tree/master/rOCCI/tests/"
FUNCTIONALITYTESTURL="https://github.com/CESNET/glite-testsuites/tree/master/rOCCI/tests/"

gen_test_report > TestRep.txt

