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
This script logs to an indicated server, downloads the L&B test suite and executes it

Prerequisities:
   - LB server (hostname given as a cmdline argument)
   - Valid proxy certificate (will be imported and used in testing)

Tests called:

	The full L&B Functional Test Suite

EndHelpHeader

	echo "Usage: $progname [OPTIONS] hostname"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " hostname               L&B server to use for testing."
}

# read common definitions and functions
COMMON=lb-common.sh
if [ ! -r ${COMMON} ]; then
	printf "Common definitions '${COMMON}' missing!"
	exit 2
fi
source ${COMMON}

#logfile=$$.tmp
#flag=0
while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		*) remotehost=$1 
			shift
			outformat=$1
			shift ;;
	esac
	shift
done

if [ -z $outformat ]; then
	outformat='-c'
fi 

# check_binaries
printf "<verbatim>\nTesting if all binaries are available"
check_binaries $GRIDPROXYINFO $SYS_GREP $SYS_SED $SYS_AWK $SYS_SCP
if [ $? -gt 0 ]; then
	test_failed
else
	test_done
fi

printf "Testing credentials"

timeleft=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^timeleft" | ${SYS_SED} "s/timeleft\s*:\s//"`

if [ "$timeleft" = "" ]; then
        test_failed
        print_error "No credentials"
else
        if [ "$timeleft" = "0:00:00" ]; then
                test_failed
                print_error "Credentials expired"
        else
                test_done

		# Get path to the proxy cert
		printf "Getting proxy cert path... "

		PROXYCERT=`${GRIDPROXYINFO} | ${SYS_GREP} -E "^path" | ${SYS_SED} "s/path\s*:\s//"`

	        if [ "$PROXYCERT" = "" ]; then
        	        test_failed
                	print_error "Unable to identify the path to your proxy certificate"
	        else
			printf "$PROXYCERT"
        	        test_done

			printf "L&B server: '$remotehost'"

			if [ "$remotehost" = "" ]; then
				test_failed
			else
				test_done

				scp $PROXYCERT root@$remotehost:/tmp/

cat << EndArrangeScript > arrange_lb_test_root.sh 
CERTFILE=\$1
GLITE_USER=\$2
LBTSTCOLS=\$3
OUTPUT_OPT=\$4


export LBTSTCOLS

yum install -q -y globus-proxy-utils 
yum install -q -y postgresql postgresql-server
yum install -q -y activemq java-1.6.0-openjdk

/etc/init.d/postgresql start
mv /var/lib/pgsql/data/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf.orig
cat >/var/lib/pgsql/data/pg_hba.conf <<EOF
local all all trust
host all all 127.0.0.1 ident sameuser
host all all ::1/128 ident sameuser
EOF
/etc/init.d/postgresql reload
createuser -U postgres -S -R -D rtm

if [ -f ~/.activemqrc ]
	echo ActiveMQ already configured
else
	activemq setup ~/.activemqrc
	activemq start
fi


cd /tmp

glite_id=\`id -u \$GLITE_USER\`

echo \$GLITE_USER user ID is \$glite_id

mv \$CERTFILE x509up_u\$glite_id
chown \$GLITE_USER:\$GLITE_USER x509up_u\${glite_id}

CVSPATH=\`which cvs\`

if [ "\$CVSPATH" = "" ]; then
        printf "CVS binary not present"
        egrep -i "Debian|Ubuntu" /etc/issue

        if [ \$? = 0 ]; then
                apt-get install --yes cvs
        else
                yum install -y cvs
        fi

fi

echo cd > arrange_lb_test_user.sh
echo export LBTSTCOLS=\$LBTSTCOLS >> arrange_lb_test_user.sh
echo export TEST_TAG_ACL=yes >> arrange_lb_test_user.sh
echo 'export GLITE_MYSQL_ROOT_PASSWORD="[Edited]"' >> arrange_lb_test_user.sh
echo mkdir LB_testing >> arrange_lb_test_user.sh
echo cd LB_testing >> arrange_lb_test_user.sh
echo cvs -d :pserver:anonymous@glite.cvs.cern.ch:/cvs/jra1mw co org.glite.testsuites.ctb/LB >> arrange_lb_test_user.sh
echo ls >> arrange_lb_test_user.sh
echo cd org.glite.testsuites.ctb/LB/tests >> arrange_lb_test_user.sh
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
echo echo ======================== >> arrange_lb_test_user.sh
echo echo "  REAL TESTS START HERE" >> arrange_lb_test_user.sh
echo echo ======================== >> arrange_lb_test_user.sh
echo 'echo "</verbatim>"' >> arrange_lb_test_user.sh
echo 'echo "<literal>"' >> arrange_lb_test_user.sh
echo sh ./lb-test-event-delivery.sh  \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-il-recovery.sh -f /var/glite/log/dglogd.log \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-job-registration.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-https.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-job-states.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-logevent.sh /var/glite/log/dglogd.log \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-notif-recovery.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-notif.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-notif-switch.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-proxy-delivery.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-ws.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-bdii.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-sandbox-transfer.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-changeacl.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-statistics.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-threaded.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-harvester.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo sh ./lb-test-notif-msg.sh \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo perl ./lb-test-purge.pl --i-want-to-purge delwin.fi.muni.cz:9000 \$OUTPUT_OPT >> arrange_lb_test_user.sh
echo 'echo "</literal>"' >> arrange_lb_test_user.sh
echo 'echo "<verbatim>"' >> arrange_lb_test_user.sh
echo echo ================== >> arrange_lb_test_user.sh
echo echo "  TESTS END HERE" >> arrange_lb_test_user.sh
echo echo ================== >> arrange_lb_test_user.sh

#echo "" >> arrange_lb_test_user.sh

chown \$GLITE_USER:\$GLITE_USER arrange_lb_test_user.sh
chmod +x arrange_lb_test_user.sh

#su -l \$GLITE_USER
su -l \$GLITE_USER --command=/tmp/arrange_lb_test_user.sh
echo "</verbatim>"

EndArrangeScript
				TERMCOLS=`stty size | awk '{print $2}'`

				chmod +x arrange_lb_test_root.sh

				scp arrange_lb_test_root.sh root@$remotehost:/tmp/

				ssh -l root $remotehost "sh /tmp/arrange_lb_test_root.sh $PROXYCERT glite $TERMCOLS $outformat"

		
			fi
		fi
	fi
fi

