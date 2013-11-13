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

function gen_arrange_script_gridsite()
{
remotehost=$1
COPYPROXY=$2

egrep -i "Debian|Ubuntu" /etc/issue
if [ $? = 0 ]; then 
        INSTALLCMD="apt-get install -q --yes --force-yes"
	INSTALLPKGS="lintian apache2 netcat-traditional psmisc"
	HTTPD_SERVER_ROOT=/etc/apache2
else
        INSTALLCMD="yum install -q -y --nogpgcheck"
	INSTALLPKGS="rpmlint httpd nc mod_ssl"
	HTTPD_SERVER_ROOT=/etc/httpd
fi

cat << EndArrangeScript > arrange_gridsite_test_root.sh 
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

${INSTALLCMD} voms-clients curl wget ca-certificates lsof sudo $INSTALLPKGS

if test -f /usr/sbin/apache2; then
	SYS_APACHE=apache2
else
	SYS_APACHE=httpd
fi

if [ -d /etc/apache2 -a ! -d /etc/apache2/modules ]; then
	ln -s ../../var/log/apache2 /etc/apache2/logs
	ln -s ../../usr/lib/apache2/modules /etc/apache2/modules
	ln -s ../../var/run/apache2 /etc/apache2/run
fi

HTTPD_CONFDIR=/tmp
for dir in /etc/httpd /etc/apache /etc/apache2; do
	if [ -d \$dir ]; then
		HTTPD_CONFDIR=\$dir
		break
	fi
done
HTTPD_CONF=\$HTTPD_CONFDIR/gridsite-webserver.conf

if getent passwd www-data >/dev/null; then
	HTTPD_USER=www-data
else
	HTTPD_USER=apache
fi

# Debian compress everything inside /usr/share/doc
HTTPD_CONF_SRC=\`ls -1 /usr/share/doc/gridsite*/httpd-webserver.conf* | head -n 1\`
if echo \$HTTPD_CONF_SRC | grep '\.gz$' >/dev/null 2>&1; then
	gzip -dc < \$HTTPD_CONF_SRC > /tmp/httpd-webserver.conf
	HTTPD_CONF_SRC=/tmp/httpd-webserver.conf
fi
if [ -z "\$HTTPD_CONF_SRC" ]; then
	echo "gridsite apache config example not found" >&2
	exit 2
fi

sed \\
	-e '1,\$s!/usr/lib/httpd/modules/!modules/!' \\
	-e 's!/var/www/html!/var/www/htdocs!' \\
	-e  "s/FULL.SERVER.NAME/\$(hostname -f)/" \\
	-e "s/\(GridSiteGSIProxyLimit\)/# \1/" \\
	-e "s,^\(ServerRoot\).*,\1 $HTTPD_SERVER_ROOT," \\
	-e "s/^User .*/User \$HTTPD_USER/" \\
	-e "s/^Group .*/Group \$HTTPD_USER/" \\
  \$HTTPD_CONF_SRC > \$HTTPD_CONF
echo "AddHandler cgi-script .cgi" >> \$HTTPD_CONF
echo "ScriptAlias /gridsite-delegation.cgi /usr/sbin/gridsite-delegation.cgi" >> \$HTTPD_CONF
# internal module?
if [ ! -f $HTTPD_SERVER_ROOT/modules/mod_log_config.so ]; then
	sed -i 's/^\(LoadModule\\s\\+log_config_module.*\)/# \1/' \$HTTPD_CONF
fi
# Fedora 18+
for mod in mpm_prefork unixd authz_core; do
	if [ -f $HTTPD_SERVER_ROOT/modules/mod_\${mod}.so ]; then
		echo "LoadModule \${mod}_module	modules/mod_\${mod}.so" >> \$HTTPD_CONF
	fi
done
# Fedora 18+:
# - dunno what should replace the shm://
# - need to explicitly enable CGI
if grep Fedora /etc/issue >/dev/null; then
	sed -i 's,^\(SSLSessionCache.*\),#\1,' \$HTTPD_CONF
	echo "Options ExecCGI" >> \$HTTPD_CONF
fi

mkdir -p /var/www/htdocs
killall httpd apache2 >/dev/null 2>&1
sleep 2
killall -9 httpd apache2 >/dev/null 2>&1
if selinuxenabled >/dev/null 2>&1; then
	# SL6 doesn't like much starting apache inside rc scripts
	# change identity 'system_u:system_r:initrc_t:s0'
	echo "SELinux enabled, don't panic!"
	# fix the sudo first
	sed -i 's/^\(Defaults.*requiretty\)/#\1/' /etc/sudoers
	echo Starting sudo -r system_r -t unconfined_t \$SYS_APACHE -f \$HTTPD_CONF
	sudo -r system_r -t unconfined_t \$SYS_APACHE -f \$HTTPD_CONF
else
	echo Starting \$SYS_APACHE -f \$HTTPD_CONF
	\$SYS_APACHE -f \$HTTPD_CONF
fi

cd /tmp

VCSPATH=\`which git\`

if [ "\$VCSPATH" = "" ]; then
        printf "git binary not present, installing..."
	${INSTALLCMD} git
	echo " done"
fi

if [ $COPYPROXY -eq 1 ]; then
	mv \$CERTFILE x509up_u\`id -u\`
	chown \`id -un\`:\`id -gn\` x509up_u\`id -u\`
else
	rm -rf /tmp/test-certs/grid-security
	[ -r glite-testsuites/LB/tests/lb-generate-fake-proxy.sh ] || wget -q -P glite-testsuites/LB/tests/ https://raw.github.com/CESNET/glite-testsuites/master/LB/tests/lb-generate-fake-proxy.sh
	chmod +x glite-testsuites/LB/tests/lb-generate-fake-proxy.sh
	glite-testsuites/LB/tests/lb-generate-fake-proxy.sh > fake-prox.out.\$\$
	FAKE_CAS=\`cat fake-prox.out.\$\$ | grep -E "^X509_CERT_DIR" | sed 's/X509_CERT_DIR=//'\`
	if [ "\$FAKE_CAS" = "" ]; then
                echo "Failed generating proxy" >&2
                exit 2
        else
                cp -rv \$FAKE_CAS/* /etc/grid-security/certificates/
        fi

	TRUSTED_CERTS=\`cat fake-prox.out.\$\$ | grep -E "^TRUSTED_CERTS" | sed 's/TRUSTED_CERTS=//'\`
	export x509_USER_CERT=\${TRUSTED_CERTS}/trusted_client00.cert
	export x509_USER_KEY=\${TRUSTED_CERTS}/trusted_client00.priv-clear
	rm fake-prox.out.\$\$
fi

if [ ! -d /etc/vomses ]; then
	echo Installing experimental VOMS server
	if [ ! -f ./px-voms-install.sh ]; then
		wget https://raw.github.com/CESNET/glite-testsuites/master/PX/tests/px-voms-install.sh
		chmod +x px-voms-install.sh
	fi
	source ./px-voms-install.sh -u root
fi

cd ~/
mkdir GridSite_testing
cd GridSite_testing
git clone --depth 0 \$GITROOT
cd glite-testsuites/gridsite/tests
echo ========================
echo "  REAL TESTS START HERE"
echo ========================
echo "</PRE>"
./ping-remote.sh $remotehost \$OUTPUT_OPT
./ping-local.sh \$OUTPUT_OPT -f \$HTTPD_CONF
./gridsite-test-all.sh \$OUTPUT_OPT
./gridsite-test-packaging.sh \$OUTPUT_OPT
./gridsite-test-build.sh \$OUTPUT_OPT
echo "<PRE>"
echo ==================
echo "  TESTS END HERE"
echo ==================
echo "</PRE>"

EndArrangeScript
}

