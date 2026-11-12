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
COMMON=`dirname $0`/gridsite-common.sh
if [ ! -r ${COMMON} ]; then
        printf "Common definitions '${COMMON}' missing!\n"
        exit 2
fi
source $COMMON

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

test_start

# check_binaries
printf "Testing if all binaries are available"
check_binaries rm cat sleep openssl sed grep
if [ $? -gt 0 ]; then
	test_failed
	test_end
	exit 2
else
	test_done
fi

# The client certificate every connection below is made with: the tester's own,
# which 'make -C tools' generated. It used to be a hardcoded path into the tree the
# deleted fake-proxy generator filled in, under a key file name (.priv-clear) the
# new generator does not use.
printf "Testing credentials"
if ! need_credentials || [ ! -r "$X509_USER_CERT" ] || [ ! -r "$X509_USER_KEY" ]; then
	test_end
	exit 2
fi

printf "Setting test.cgi..."
cat >$GS_HTDOCS/.gacl <<EOF
<gacl>
  <entry>
    <person>
      <dn>`credentials_dn`</dn>
    </person>
    <allow><read/></allow>
  </entry>
</gacl>
EOF

cat >$GS_HTDOCS/test.cgi <<EOF
#!/bin/sh
echo 'Content-type: text/plain'
echo
printenv
EOF

cat > $DATA <<EOF
GET /test.cgi HTTP/1.1
User-Agent: glite-testsuites/0.0 (linux) openssl/`openssl version | cut -f2 -d' '`
Host: $GS_SERVER
Accept: */*

EOF

	# Whether any of that arrived. The test_done here used to be unconditional, so a
	# document root the tester cannot write to still reported the setup as done and
	# every check below then failed on a CGI that was never there.
	if [ ! -s "$GS_HTDOCS/test.cgi" ] || [ ! -s "$GS_HTDOCS/.gacl" ] || [ ! -s "$DATA" ]; then
		test_failed
		print_error "cannot write into $GS_HTDOCS as $(id -un) - run setup.sh -u $(id -un), or
    setfacl -R -m u:$(id -un):rwX -d -m u:$(id -un):rwX $GS_HTDOCS"
		test_end
		exit 2
	fi
	# Left executable by gridsite-test-all.sh, which runs first and chmod's its own
	# copy; nothing guaranteed that, so do it here as well.
	chmod +x "$GS_HTDOCS/test.cgi"
	test_done

printf "Testing test.cgi..."
(cat $DATA; sleep 0.5) | openssl s_client -crlf -connect $GS_SERVER:$GS_PORT -CApath "$GS_CAPATH" -cert "$X509_USER_CERT" -key "$X509_USER_KEY" >$OUTPUT 2>$ERROR
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
	echo -n | openssl s_client -crlf -connect $GS_SERVER:$GS_PORT -CApath "$GS_CAPATH" -cert "$X509_USER_CERT" -key "$X509_USER_KEY" -sess_out $SESSION -quiet -no_ign_eof $args 2>$ERROR
	if [ $? -eq 0 ]; then
		test_done
	else
		test_skipped
		print_info "Sessions not supported"
		break
	fi

	printf "Test for GRST_CRED_AURI_2 $args..."
	(cat $DATA; sleep 0.5) | openssl s_client -crlf -connect $GS_SERVER:$GS_PORT -CApath "$GS_CAPATH" -cert "$X509_USER_CERT" -key "$X509_USER_KEY" -sess_in $SESSION $args >$OUTPUT 2>$ERROR
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
