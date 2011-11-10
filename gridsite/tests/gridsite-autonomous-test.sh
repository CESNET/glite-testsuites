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

# read common definitions and functions
for COMMON in gridsite-common.sh test-common.sh gridsite-common-testbeds.sh
do
	if [ ! -r ${COMMON} ]; then
		printf "Downloading common definitions '${COMMON}'"
		wget -O ${COMMON} http://jra1mw.cvs.cern.ch/cgi-bin/jra1mw.cgi/org.glite.testsuites.ctb/gridsite/tests/$COMMON?view=co > /dev/null
		if [ ! -r ${COMMON} ]; then
			exit 2
		else 
			test_done
		fi
	fi
done
source gridsite-common.sh
source gridsite-common-testbeds.sh

STARTTIME=`date +%s`

printf "Getting the 'install' script... "
#XXX Provisional. The test won't be generated here in the future. Just downloaded or otherwise obtained
SCENARIO="Clean installation"
cat << EndInstallScript > GridSiteInstall.sh
rpm -Uvhi http://download.fedora.redhat.com/pub/epel/5/x86_64/epel-release-5-4.noarch.rpm
yum install -y yum-priorities yum-protectbase
rpm -i http://emisoft.web.cern.ch/emisoft/dist/EMI/1/sl5/x86_64/base/emi-release-1.0.0-1.sl5.noarch.rpm

#cd /etc/yum.repos.d/
#wget http://etics-repository.cern.ch/repository/pm/registered/repomd/id/2efadb29-61fb-4d5f-be8f-17b799a269e0/sl5_x86_64_gcc412EPEL/etics-registered-build-by-id-protect.repo
#echo priority=45 >> etics-registered-build-by-id-protect.repo

yum install -y gridsite-apache gridsite-commands gridsite-debuginfo gridsite-devel.x86_64 gridsite-gsexec gridsite-service-clients gridsite-services gridsite-shared
EndInstallScript
test_done


printf "Generating the 'arrange' script... "
gen_arrange_script `hostname -f` 0
test_done


printf "Installing... "
sh GridSiteInstall.sh > Install_log.txt 2> Install_err.log
test_done

printf "Running tests... "
sh arrange_gridsite_test_root.sh none glite 80 '-x' > test_log.txt 2> test_err.log
test_done

ENDTIME=`date +%s`

DURATION=`expr $ENDTIME - $STARTTIME`

ISSUE=`cat /etc/issue | head -n 1`
PLATFORM=`uname -i`
TESTBED=`hostname -f`
DISTRO=`cat /etc/issue | head -n 1 | sed 's/\s.*$//'`
VERSION=`cat /etc/issue | head -n 1 | grep -E -o "[0-9]+\.[0-9]+"`
MAJOR=`echo $VERSION | sed 's/\..*$//'`

# Generate final report snippet

printf "
---++ $SCENARIO, $DISTRO $MAJOR

---+++ Environment
#CleanInstallation

Clean installation according to EMI guidelines (CA certificates, proxy certificate...).

| OS Issue | $ISSUE |
| Platform | $PLATFORM |
| Host | $TESTBED |
| Duration | `expr $DURATION / 60` min |
| Testbed uptime | =`uptime | sed 's/^\s*//'`= |

---++++ Process
<verbatim>\n" > report.twiki

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


