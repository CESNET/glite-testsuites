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
Testing SSL session reuse

https://github.com/CESNET/gridsite/issues/10

Prerequisities:
   - GridSite and httpd with mod_ssl installed and launched
   - Generated fake certificates

Returned values:
    Exit TEST_OK: Test Passed
    Exit TEST_ERROR: Test Failed
    Exit 2: Wrong Input

EndHelpHeader

	echo "Usage: $progname [OPTIONS]"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -o | --output 'file'   Redirect all output to the 'file' (stdout by default)."
	echo " -t | --text            Format output as plain ASCII text."
	echo " -c | --color           Format output as text with ANSI colours (autodetected by default)."
	echo " -x | --html            Format output as html."
}

# read common definitions and functions
for COMMON in gridsite-common.sh ../../LB/tests/lb-common.sh
do
        if [ ! -r ${COMMON} ]; then
                printf "Common definitions '${COMMON}' missing!"
                exit 2
        fi
        source $COMMON
done

while test -n "$1"
do
        case "$1" in
                "-h" | "--help") showHelp && exit 2 ;;
                "-t" | "--text")  setOutputASCII ;;
                "-c" | "--color") setOutputColor ;;
                "-x" | "--html")  setOutputHTML ;;
        esac
        shift
done


##
#  Starting the test
#####################

SESSION=/tmp/$progname.session.$$.dat
DATA=/tmp/$progname.data.$$.txt
OUTPUT=/tmp/$progname.output.$$.txt
ERROR=/tmp/$progname.error.$$.txt
UCERT=/tmp/test-certs.root/trusted-certs/trusted_client00.cert
UKEY=/tmp/test-certs.root/trusted-certs/trusted_client00.priv-clear
#UCERT=/etc/grid-security/hostcert.pem
#UKEY=/etc/grid-security/hostkey.pem


test_start

# check_binaries
printf "Testing if all binaries are available"
check_binaries rm openssl sed
if [ $? -gt 0 ]; then
	test_failed
	test_end
	exit 2
else
	test_done
fi

printf "Setting test.cgi..."
cat >/var/www/htdocs/.gacl <<EOF
<gacl>
  <entry>
    <person>
      <dn>`openssl x509 -noout -subject -in ${UCERT} | sed -e 's/^subject= //'`</dn>
    </person>
    <allow><read/></allow>
  </entry>
</gacl>
EOF

cat >/var/www/htdocs/test.cgi <<EOF
#!/bin/sh
echo 'Content-type: text/plain'
echo
printenv
EOF

cat > $DATA <<EOF
GET /test.cgi HTTP/1.1
User-Agent: glite-testsuites/0.0 (linux) openssl/`openssl version | cut -f2 -d' '`
Host: `hostname -f`
Accept: */*

EOF
test_done

printf "Testing test.cgi..."
(cat $DATA; sleep 0.5) | openssl s_client -connect `hostname -f`:443 -CApath /etc/grid-security/certificates -cert $UCERT -key $UKEY >$OUTPUT 2>$ERROR
ret=$?
grep -q '^GRST_' $OUTPUT
if [ $ret -eq 0 -a $? -eq 0 ]; then
	test_done
else
	test_failed
	test_end
	exit 2
fi

for args in '' '-no_ticket '; do
	rm -f $SESSION

	printf "Launching first SSL session..."
	echo -n | openssl s_client -connect `hostname -f`:443 -CApath /etc/grid-security/certificates -cert $UCERT -key $UKEY -sess_out $SESSION -quiet -no_ign_eof $args 2>$ERROR
	if [ $? -eq 0 ]; then
		test_done
	else
		test_skipped
		print_info "Sessions not supported"
		break
	fi

	printf "Test for GRST_CRED_AURI_2 $args..."
	(cat $DATA; sleep 0.5) | openssl s_client -connect `hostname -f`:443 -CApath /etc/grid-security/certificates -cert $UCERT -key $UKEY -sess_in $SESSION $args >$OUTPUT 2>$ERROR
	if [ $? -ne 0 ]; then
		test_failed
		print_error "SSL connection failed!"
		TEST_OK=$TEST_ERROR
		continue
	fi

	grep -q '^GRST_CRED_AURI_2' $OUTPUT
	if [ $? -ne 0 ]; then
		test_failed
		print_error "GRST_CRED_AURI_2 missing!"
		TEST_OK=$TEST_ERROR
		continue
	fi
	test_done
done

rm -f /tmp/$progname.data.*.txt
rm -f /tmp/$progname.error.*.txt
rm -f /tmp/$progname.output.*.txt
rm -f /tmp/$progname.session.*.dat

test_end

exit $TEST_OK
