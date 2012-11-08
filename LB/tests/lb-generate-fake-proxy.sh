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
user_id=`id -u`
CERTS_ROOT=/tmp/test-certs.`id -un`
USER=trusted_client00
USER_BOB=trusted_client01
USER_SHA512=trusted_clientsha512
VOMS_SERVER=trusted_host
VO=vo.org

showHelp()
{
cat << EndHelpHeader
Script for making fake proxy certificates out of fake credentials
Thist script generates 2 proxy certificates with voms attributes
and sets \$X509_USER_PROXY and \$X509_USER_PROXY_BOB
Prerequisities:

Tests called:

Returned values:
    Exit 0: Certificate generated
    Exit 1: Certificete not generated

EndHelpHeader
	echo "Usage: $progname [OPTIONS]"
        echo "Options:"
        echo " -h | --help            Show this help message."
        echo " -H | --hours           Proxy will be valid for given No. of hours (default is 12)"
        echo " -l | --lsc             Generate VOMS lsc file."
        echo " -V | --novoms          Skip VOMS stuff."
	echo " -o | --old	      Create old-style non-RFC proxy."
	echo " -a | --all	      Generate all certificates."

}

GENLSC=0
VOMS=1
RFCSWITCH="-rfc"
GEN_ALL=""
while test -n "$1"
do
        case "$1" in
                "-h" | "--help") showHelp && exit 2 ;;
                "-H" | "--hours") shift ; PROXYHOURS="-hours $1 " ;;
                "-l" | "--lsc") GENLSC=1 ;;
                "-V" | "--novoms") VOMS=0 ;;
                "-o" | "--old") RFCSWITCH="" ;;
		"-a" | "--all")	GEN_ALL="--all" ;;
        esac
        shift
done

PWD=`pwd`

if [ ! -d "$CERTS_ROOT" -o ! -e "${CERTS_ROOT}/trusted-certs/trusted_clientsha512.cert" ]; then
	echo "Generating fake proxy certificate - this may take a few minutes"
	echo ""

	mkdir -p $CERTS_ROOT
	cd $CERTS_ROOT
	wget -q -O org.glite.security.test-utils.tar.gz \
		'http://jra1mw.cvs.cern.ch:8180/cgi-bin/jra1mw.cgi/org.glite.security.test-utils.tar.gz?view=tar' &> /dev/null || exit 1
	tar xzf org.glite.security.test-utils.tar.gz || exit 1
	# keep using system default hash (even when different across openssl versions)
	sed -i.orig 's/openssl x509 -subject_hash_old/openssl x509 -hash/' org.glite.security.test-utils/bin/generate-test-certificates.sh
	org.glite.security.test-utils/bin/generate-test-certificates.sh\
	$GEN_ALL $CERTS_ROOT &> /dev/null || exit 1
fi

cd $CERTS_ROOT/trusted-certs

for p in $USER $VOMS_SERVER $USER_BOB $USER_SHA512; do
	openssl rsa -in ${p}.priv -out ${p}.priv-clear -passin pass:changeit &> /dev/null
	chmod 600 ${p}.priv-clear
	done

if [ $VOMS -eq 1 ]; then
	for p in $USER $USER_BOB; do
		voms-proxy-fake -cert ${p}.cert -key ${p}.priv-clear $RFCSWITCH\
			-hostcert ${VOMS_SERVER}.cert -hostkey ${VOMS_SERVER}.priv-clear $PROXYHOURS\
			-voms ${VO} -out /tmp/x509up_u${p} \
			-fqan "/${VO}/Role=NULL/Capability=NULL" &> /dev/null || exit 1
		done
	mv "/tmp/x509up_u${USER}" "/tmp/x509up_u${user_id}"
	mv "/tmp/x509up_u${USER_BOB}" "/tmp/x509up_u.${user_id}"
	export X509_USER_PROXY=/tmp/x509up_u${user_id}
	export X509_USER_PROXY_BOB=/tmp/x509up_u.${user_id}
	echo "/tmp/x509up_u${user_id} proxy certificate has been generated"
	echo "/tmp/x509up_u.${user_id} proxy certificate has been generated" 
fi

export x509_USER_CERT=$CERTS_ROOT/trusted-certs/trusted_client00.cert
export x509_USER_KEY=$CERTS_ROOT/trusted-certs/trusted_client00.priv-clear

echo ""
echo "======================================================================"
echo "Credentials have been generated, adapt your configuration accordingly:"
echo "======================================================================"

echo X509_CERT_DIR=$CERTS_ROOT/grid-security/certificates
echo TRUSTED_CERTS=$CERTS_ROOT/trusted-certs
echo HOST_CERT_DIR=$CERTS_ROOT/grid-security
if [ $VOMS -eq 1 ]; then
	echo X509_USER_PROXY=/tmp/x509up_u${user_id}
	#BOB'S FAKE PROXY
	echo X509_USER_PROXY_BOB=/tmp/x509up_u.${user_id}
	if [ $GENLSC -eq 1 ]; then
		mkdir -p /etc/grid-security/vomsdir/$VO
		openssl x509 -noout -subject -issuer -in $CERTS_ROOT/trusted-certs/${VOMS_SERVER}.cert | cut -d ' ' -f 2- > /etc/grid-security/vomsdir/$VO/`hostname -f`.lsc
	else
		echo mkdir /etc/grid-security/vomsdir/$VO
		echo "openssl x509 -noout -subject -issuer -in $CERTS_ROOT/trusted-certs/${VOMS_SERVER}.cert | cut -d ' ' -f 2- > /etc/grid-security/vomsdir/$VO/`hostname -f`.lsc"
	fi
fi
echo "======================================================================"
echo ""

cd $PWD
