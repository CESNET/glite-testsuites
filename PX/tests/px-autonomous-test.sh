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
This script is intended for running a fully automated deployment and functionality test of MyProxy configurations and proxy renewal

Prerequisities:
New empty machine, certificates

Tests called:
	Deployment
	The full PX Functional Test Suite

EndHelpHeader

	echo "Usage: $progname [OPTIONS] hostname"
	echo "Options:"
	echo " -h | --help            Show this help message."
}

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
for COMMON in px-common.sh test-common.sh px-common-testbeds.sh
do
	if [ ! -r ${COMMON} ]; then
		printf "Downloading common definitions '${COMMON}'"
		wget -q https://raw.github.com/CESNET/glite-testsuites/master/PX/tests/$COMMON
		if [ ! -r ${COMMON} ]; then
			exit 2
		else
			test_done
		fi
	fi
done
source px-common.sh
source px-common-testbeds.sh
#also read L&B common definitions for common functions.
for COMMON in lb-common-testbeds.sh
do
	if [ ! -r ${COMMON} ]; then
		if [ -r `dirname $0`/../../LB/tests/${COMMON} ]; then
			printf "Creating symbolic link for '${COMMON}'"
			ln -s ../../LB/tests/${COMMON} .
			test_done
		else
			printf "Downloading common definitions '${COMMON}'"
			wget -q https://raw.github.com/CESNET/glite-testsuites/master/LB/tests/$COMMON
			if [ ! -r ${COMMON} ]; then
				exit 2
			else
				test_done
			fi
		fi
	fi
done
source lb-common-testbeds.sh


printf "Getting the 'install' script... "
# Example script, for real tests it should be downloaded or otherwise obtained
SCENARIO=${SCENARIO:-"Clean installation"}
test -s PXinstall.sh || cat << EndInstallScript > PXinstall.sh
rpm -Uvhi http://dl.fedoraproject.org/pub/epel/5/x86_64/epel-release-5-4.noarch.rpm
yum install -y yum-priorities yum-protectbase
rpm -i http://emisoft.web.cern.ch/emisoft/dist/EMI/1/sl5/x86_64/base/emi-release-1.0.0-1.sl5.noarch.rpm

#cd /etc/yum.repos.d
#wget http://etics-repository.cern.ch/repository/pm/registered/repomd/id/f850dc7c-4774-4b6f-98cf-5bb7eb205d18/sl5_x86_64_gcc412EPEL/etics-registered-build-by-id-protect.repo
#echo priority=45 >> etics-registered-build-by-id-protect.repo

yum install -y emi-px glite-px-proxyrenewal

cd ~/
mkdir -m 700 yaim
cd yaim

cat << EOF > site-info.def
SITE_NAME=krakonosovo
PX_HOST=\`hostname -f\`
GRID_AUTHORIZED_RETRIEVERS="\*"
GRID_AUTHORIZED_RENEWERS="\`openssl x509 -in /etc/grid-security/hostcert.pem -noout -subject |sed -e 's/subject= //'\`"
EOF

sed -i 's/155/255/g' /opt/glite/yaim/examples/edgusers.conf
sed -i 's/156/256/g' /opt/glite/yaim/examples/edgusers.conf

/opt/glite/yaim/bin/yaim -c -s ./site-info.def -n glite-PX

mkdir ~glite/.certs
cp /etc/grid-security/host* ~glite/.certs/
chown -R glite ~glite/.certs/

export GLITE_USER=glite
export GLITE_HOST_KEY=/home/glite/.certs/hostkey.pem
export GLITE_HOST_CERT=/home/glite/.certs/hostcert.pem

/etc/init.d/glite-proxy-renewald start
EndInstallScript
test_done


printf "Generating the 'arrange' script... "
gen_arrange_script_px `hostname -f` 0
test_done


printf "Installing... "
sh PXinstall.sh > Install_log.txt 2> Install_err.log && test_done || test_failed

printf "Running tests... "
sh arrange_px_test_root.sh none glite 80 '-x' > test_log.txt 2> test_err.log && test_done || test_failed

printf "Collecting package list... "
gen_repo_lists ./prod_packages.txt ./repo_packages.txt
test_done

ENDTIME=`date +%s`

#Generating report section
gen_deployment_header $ENDTIME $STARTTIME "$SCENARIO" > $REPORT

echo "$SCENARIO" | grep -E -i "upgrade|update" > /dev/null
if [ $? -eq 0 ]; then
	printf "
<A NAME=\"${ID}-ProdRepo\"></A><H4>Production Repo Contents</H4>

<PRE>\n" >> $REPORT
	cat ./prod_packages.txt >> $REPORT
	printf "</PRE>\n" >> $REPORT
fi

printf "
<A NAME=\"${ID}-TestRepo\"></A><H4>Test Repo Contents</H4>

<PRE>\n" >> $REPORT
cat ./repo_packages.txt >> $REPORT
printf "</PRE>

<A NAME=\"${ID}-Process\"></A><H4>Process</H4>

<PRE>\n" >> $REPORT
cat PXinstall.sh >> $REPORT
printf "</PRE>

<A NAME=\"${ID}-Output\"></A><H4>Full Output of the Installation</H4>

<PRE>\n" >> $REPORT
cat Install_log.txt >> $REPORT

printf "</PRE>

<A NAME=\"${ID}-Tests\"></A><H3>Tests</H3>

<table>
<tr><td> TestPlan </td><td> <A HREF=\"https://twiki.cern.ch/twiki/bin/view/EGEE/PXSoftwareVerificationandValidationPlan\">https://twiki.cern.ch/twiki/bin/view/EGEE/PXSoftwareVerificationandValidationPlan</A> </td></tr>
<tr><td> Tests </td><td> <A HREF=\"https://twiki.cern.ch/twiki/bin/view/EGEE/PXSoftwareVerificationandValidationPlan\">https://twiki.cern.ch/twiki/bin/view/EGEE/PXSoftwareVerificationandValidationPlan</A> </td></tr>
</table>

<PRE>\n" >> $REPORT
cat test_log.txt >> $REPORT

#Generating test report

PRODUCT="emi.px"
UNITESTEXEC="NO"
REMARKS="No unit tests implemented"
PERFORMANCEEXEC="NO"
TESTREPOCONTENTS="`cat ./repo_packages.txt`"
PRODREPOCONTENTS="`cat ./prod_packages.txt`"
INSTALLCOMMAND="`cat PXinstall.sh`"
INSTALLLOG="`cat Install_log.txt`"
CONFIGLOG="Configuration log shown with the installation log, see directly above"
#UPGRADECMD
UNITTESTURL="NA"
TESTPLANURL="https://github.com/CESNET/glite-testsuites/tree/master/PX/tests/"
FUNCTIONALITYTESTURL="https://twiki.cern.ch/twiki/bin/view/EGEE/SA3Testing#PX"

gen_test_report > TestRep.txt

