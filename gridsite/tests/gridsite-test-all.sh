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
Script for testing gridsite functions: the .gacl read, write, list and delete
permissions, the environment the CGI is handed, the gridsite client commands, proxy
delegation and the VOMS .lsc handling.

Prerequisities:
   - GridSite and httpd with mod_ssl installed, serving this host on port 443
     with the configuration setup.sh wrote
   - test credentials (make -C tools) and a document root the tester can write
   - a VOMS server named in /etc/vomses, for the .lsc part

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
source ${COMMON}

logfile=$$.tmp
flag=0
while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		"-o" | "--output") shift ; logfile=$1 flag=1 ;;
		"-t" | "--text")  setOutputASCII ;;
		"-c" | "--color") setOutputColor ;;
		"-x" | "--html")  setOutputHTML ;;
	esac
	shift
done

# redirecting all output to $logfile
#touch $logfile
#if [ ! -w $logfile ]; then
#	echo "Cannot write to output file $logfile"
#	exit $TEST_ERROR
#fi

DEBUG=2

##
#  Starting the test
#####################

{
test_start


# check_binaries
printf "Testing if all binaries are available"
# Every program this script runs. The list used to name htcp, htls and openssl
# twice each while leaving out htproxyput, htproxyrenew and htproxyunixtime, so a
# testbed without the delegation clients passed this line and then failed every
# check that needed one of them.
check_binaries curl rm chown openssl grep awk sed tail head sort id \
	htcp htls htmv htrm htproxyput htproxyrenew htproxyunixtime htproxydestroy \
	voms-proxy-info voms-proxy-init
if [ $? -gt 0 ]; then
	test_failed
else
	test_done
fi

# The identity this test presents and the proxy it delegates with are the tester's
# own: 'make -C tools' made them and credentials_env exported their paths. They
# used to be hardcoded into /tmp/test-certs.root, the tree the deleted fake-proxy
# generator filled in, under a key file name (.priv-clear) the new one does not use.
printf "Testing credentials"
if ! need_credentials; then
	test_end
	exit 2
fi
if [ ! -r "$X509_USER_CERT" ] || [ ! -r "$X509_USER_KEY" ]; then
	print_error "No user certificate in $X509_USER_CERT and $X509_USER_KEY - the .gacl entries below are made out of its subject"
	test_end
	exit 2
fi

printf "Proxy status:$lf<PRE>$lf"
voms-proxy-info
printf "</PRE>$lf"

	# The document root of the server under test, which everything below drops
	# .gacl files and a test.cgi into. setup.sh creates it and makes it writable by
	# the tester as well as by the server; finding that out once, here, is what
	# keeps a testbed that was never configured from reporting forty failures.
	printf "Testing that the document root $GS_HTDOCS is writable"
	if [ -d "$GS_HTDOCS" ] && touch "$GS_HTDOCS/.writable-$$" 2> /dev/null; then
		rm -f "$GS_HTDOCS/.writable-$$"
		test_done
	else
		test_failed
		print_error "Cannot write into $GS_HTDOCS as $(id -un) - as root, run setup.sh -u $(id -un), or
    setfacl -R -m u:$(id -un):rwX -d -m u:$(id -un):rwX $GS_HTDOCS $GS_PROXYCACHE"
		test_end
		exit 2
	fi

	printf "READ (Read Permissions)\n"

cat >$GS_HTDOCS/test.html <<EOF
<html><body><h1>Hello Grid</h1></body></html>
EOF

	$SYS_RM $GS_HTDOCS/.gacl

	printf "Plain read... "
	code=`curl --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" --output /dev/null --silent --write-out '%{http_code}\n'  https://$GS_SERVER/test.html`
	printf "Return code $code"
	if [ "$code" = "403" ]; then 
		test_done
	else
		test_failed
	fi

cat >$GS_HTDOCS/.gacl <<EOF
<gacl>
  <entry>
    <any-user/>
      <allow><read/></allow>
  </entry>
</gacl>
EOF


	printf "With gacl... "
	code=`curl --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" --output /dev/null --silent --write-out '%{http_code}\n'  https://$GS_SERVER/test.html`
	printf "Return code $code"
	if [ "$code" = "200" ]; then 
		test_done
	else
		test_failed
	fi


	printf "Get index (list & read permissions)\n"

	printf "Plain read... "
	code=`curl --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" --output /dev/null --silent --write-out '%{http_code}\n' https://$GS_SERVER/`
	printf "Return code $code"
	if [ "$code" = "403" ]; then 
		test_done
	else
		test_failed
	fi

	# The first .gacl naming the tester's own DN. It has to be spelled the way
	# mod_gridsite compares DNs - one line, slash separated - which is what
	# credentials_dn() asks OpenSSL for. The 'openssl x509 -noout -subject' these
	# lines used to run prints 'C=UG, L=Tropic, ..., CN=somebody' on OpenSSL 3, and
	# a DN in that form matches nothing: every read the ACL allows would answer 403.
cat >$GS_HTDOCS/.gacl <<EOF
<gacl>
  <entry>
    <person>
      <dn>`credentials_dn`</dn>
    </person>
    <allow><read/><list/></allow>
  </entry>
</gacl>
EOF

	printf "With gacl... "
	code=`curl --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" --output /dev/null --silent --write-out '%{http_code}\n' \
https://$GS_SERVER/`
	printf "Return code $code"
	if [ "$code" = "200" ]; then 
		test_done
	else
		test_failed
	fi




	printf "WRITE & DELETE (write permissions)\n"

	rm -f $GS_HTDOCS/.gacl $GS_HTDOCS/test.txt
	date > /tmp/test.txt
	# Making the document root writable by the server, which is what lets the
	# upload and htcp checks below create a file at all. Unprivileged this is the
	# narrow sudo rule setup.sh installs; without it gs_chown says so and the ACLs
	# setup.sh left on the directory do the job instead.
	gs_chown "$GS_HTTPD_USER" "$GS_HTDOCS" \
		|| print_warning "could not change ownership; relying on the access rights setup.sh gave $GS_HTDOCS"

	printf "Plain write... "
	code=`curl --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" --output /dev/null --silent --write-out '%{http_code}\n' --upload-file /tmp/test.txt https://$GS_SERVER/test.txt`
	printf "Return code $code"
	if [ "$code" = "403" ]; then 
		test_done
	else
		test_failed
	fi
	printf "File not created by plain write... "
	if [ -f "$GS_HTDOCS"/test.txt ]; then
		test_failed
	else
		test_done
	fi

cat >$GS_HTDOCS/.gacl <<EOF
<gacl>
  <entry>
    <person>
      <dn>`credentials_dn`</dn>
    </person>
    <allow><write/></allow>
  </entry>
</gacl>
EOF

	printf "With gacl... "
	code=`curl --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" --output /dev/null --silent --write-out '%{http_code}\n' --upload-file /tmp/test.txt https://$GS_SERVER/test.txt`
	sudo cmp -s /tmp/test.txt $GS_HTDOCS/test.txt
	uploaded=$?
	printf "Return code $code"
	# What arrived has to be what was sent, not merely accepted. The comparison was
	# already here, but the printf above the condition overwrote its status, so the
	# check compared the exit status of the printf - always zero - with 201.
	if [ "$uploaded" -eq 0 ] && [ "$code" = "201" ]; then
		test_done
	else
		test_failed
	fi

	printf "Try deletion... "
	mv  $GS_HTDOCS/.gacl $GS_HTDOCS/.gacl.bak
	code=`curl --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" --output /dev/null --silent --write-out '%{http_code}\n' -X DELETE https://$GS_SERVER/test.txt`
	printf "Return code $code"
	# The status of the printf above it, which cannot fail, used to be half of this
	# condition as well.
	if [ "$code" = "403" ]; then
		test_done
	else
		test_failed
	fi

	mv $GS_HTDOCS/.gacl.bak $GS_HTDOCS/.gacl

	printf "With gacl... "
	code=`curl --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" --output /dev/null --silent --write-out '%{http_code}\n' -X DELETE https://$GS_SERVER/test.txt`
	printf "Return code $code"
	if [ "$code" = "200" ]; then
		test_done
	else
		test_failed
	fi
	# Back to the ownership it had. Cosmetic: what the checks above measured was
	# the code the server answered with, and that came from the .gacl file, not from
	# who owns the directory.
	gs_chown root "$GS_HTDOCS" || print_warning "left $GS_HTDOCS as it was"


	printf "Checking attributes passed on to the environment\n"

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

	
	printf "Run test.cgi... "
	chmod +x $GS_HTDOCS/test.cgi
	code=`curl --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" --output /tmp/gridsite.log --silent --write-out '%{http_code}\n'  https://$GS_SERVER/test.cgi`
	printf "Return code $code"
	if [ "$code" = "200" ]; then 
		test_done
	else
		test_failed
	fi
	printf "Check for GRST_* variables... "
grep "^GRST_" /tmp/gridsite.log >/dev/null 2>/dev/null
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi


	printf "Test the basic commands (htcp, htls, htmkdir, htmv, htrm)\n"

cat >$GS_HTDOCS/.gacl <<EOF
<gacl>
  <entry>
    <person>
      <dn>`credentials_dn`</dn>
    </person>
    <allow><read/><write/><list/></allow>
  </entry>
</gacl>
EOF

	# Same as before the upload checks: the server has to be able to create files
	# in the document root for the commands below to have anything to do.
	gs_chown "$GS_HTTPD_USER" "$GS_HTDOCS" \
		|| print_warning "could not change ownership; relying on the access rights setup.sh gave $GS_HTDOCS"
	$SYS_RM $GS_HTDOCS/test.txt
	$SYS_RM $GS_HTDOCS/test2.txt
	date > /tmp/test.txt

	# The arguments as text, for the report. printf with the values as arguments
	# and the format fixed, because the paths are data: an apostrophe or a % in
	# one of them must not become part of the format. $lf is the exception - it is
	# part of the format, where it is a newline in text and a <br> in HTML; as an
	# argument it would print as the two characters \n.
	printf "Running GridSite commands with arguments --cert %s --key %s --capath %s /tmp/test.txt https://%s/$lf" \
		"$X509_USER_CERT" "$X509_USER_KEY" "$GS_CAPATH" "$GS_SERVER"

	printf "Testing htcp... "
	htcp --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" /tmp/test.txt https://$GS_SERVER/
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi
	printf "Checking by htls... "
	htls --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" https://$GS_SERVER/test.txt > /dev/null
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi
	printf "Testing htmv... "
	htmv --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" https://$GS_SERVER/test.txt https://$GS_SERVER/test2.txt
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi
	printf "htcp, file 2... "
		htcp --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" https://$GS_SERVER/test2.txt /tmp
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi
	printf "Testing htrm... "
	htrm --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" https://$GS_SERVER/test2.txt
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi
	printf "Checking by htls... "
	htls --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" https://$GS_SERVER/test2.txt 2> /dev/null
	if [ $? -eq 22 ]; then 
		test_done
	else
		test_failed
	fi
	printf "Checking directory contents with htls... "
	htls --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" https://$GS_SERVER/ > /dev/null
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi
	printf "File compare... "
	cmp /tmp/test.txt /tmp/test2.txt
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi

	# Back to the ownership it had; see the note after the upload checks.
	gs_chown root "$GS_HTDOCS" || print_warning "left $GS_HTDOCS as it was"

	printf "Test proxy delegation\n"

	# The proxy cache is where mod_gridsite stores what a delegation hands over.
	# setup.sh creates it and makes it writable by the server; making it here would
	# need root, and would leave its mode to whichever test happened to run first.
	# Without the directory none of the four checks below can do anything, so they
	# are said to be skipped instead of left to fail on their own.
	if [ ! -d "$GS_PROXYCACHE" ]; then
		printf "Proxy cache $GS_PROXYCACHE"
		test_skipped
		print_error "is not present - setup.sh creates it (docs/gridsite.md)"
	else
		gs_chown "$GS_HTTPD_USER" "$GS_PROXYCACHE" \
			|| print_warning "could not change ownership; relying on the access rights setup.sh gave it"

		#delegation
		id=`htproxyput --cert "$X509_USER_PROXY" --key "$X509_USER_PROXY" --capath "$GS_CAPATH" https://$GS_SERVER/gridsite-delegation.cgi`
		printf "id: $id"
		# Only whether a delegation id came back. The condition also used to test the
		# exit status of the printf above it, which cannot fail.
		if [ -n "$id" ]; then
			test_done
		else
			test_failed
		fi

		expiry=`htproxyunixtime --cert "$X509_USER_PROXY" --key "$X509_USER_PROXY" --capath "$GS_CAPATH" --delegation-id $id https://$GS_SERVER/gridsite-delegation.cgi`

		newid=`htproxyrenew --cert "$X509_USER_PROXY" --key "$X509_USER_PROXY" --capath "$GS_CAPATH" --delegation-id $id https://$GS_SERVER/gridsite-delegation.cgi`
		printf "newid: $newid"
		if [ -n "$newid" ]; then
			test_done
		else
			test_failed
		fi

		htproxydestroy --cert "$X509_USER_PROXY" --key "$X509_USER_PROXY" --capath "$GS_CAPATH" --delegation-id $id https://$GS_SERVER/gridsite-delegation.cgi
	fi


	printf "Test handling of VOMS .lsc files (Regression test for bug #39254 and #82023)\n"

	if [ ! -e "$X509_USER_PROXY" ]; then
		printf "No proxy certificate"
		test_skipped
	else

	# Add read permissions for any user to .gacl
	sed -i 's/<\/gacl>/<entry><any-user\/><allow><read\/><\/allow><\/entry><\/gacl>/' $GS_HTDOCS/.gacl

	FQAN=`voms-proxy-info --fqan`

	# First with no VOMS trust files to be found: the server must then ignore the
	# VOMS extensions in the proxy and report no GRST_CRED_2 at all. Emptying
	# /etc/grid-security/vomsdir is the one thing in this suite that belongs to
	# root, so it goes through the small program setup.sh installed for exactly
	# that, and the trap puts the files back even if this script dies in between -
	# the version this replaces moved them with no such safety net.
	printf "Trying with empty vomsdir. GRST_CRED_2 should not be present... "
	if ! gs_vomsdir hide; then
		test_skipped
		print_error "cannot hide /etc/grid-security/vomsdir as $(id -un) - setup.sh installs the sudo rule and the program it names"
	else
		trap 'gs_vomsdir restore > /dev/null 2>&1' EXIT INT TERM
		GRST_CRED_2=`curl --cert "$X509_USER_PROXY" --key "$X509_USER_PROXY" --capath "$GS_CAPATH" --cacert "$X509_USER_PROXY" --silent https://$GS_SERVER/test.cgi|grep GRST_CRED_2`
		if [ "$GRST_CRED_2" = "" ]; then
			test_done
		else
			print_error "returned: $GRST_CRED_2"
			test_failed
		fi
		gs_vomsdir restore > /dev/null 2>&1 \
			|| print_warning "could not put /etc/grid-security/vomsdir back - as root: ${GS_VOMS_TOGGLE:-/usr/libexec/glite-testsuites/gridsite-vomsdir} restore"
		trap - EXIT INT TERM
	fi

	# A proxy carrying VOMS extensions issued by the test CA cannot be confirmed by
	# any .lsc file, so get a real one from the VOMS server in /etc/vomses instead.
	# The two variables were spelled $x509_USER_KEY and $x509_USER_CERT here, which
	# nothing ever exported, so the regeneration quietly used the defaults.
	UTOPIA=`voms-proxy-info -all | grep -A 100 "extension information" | grep "^issuer" | grep "L=Tropic" | grep "O=Utopia" | grep "OU=Relaxation"`
	if [ "$UTOPIA" != "" ]; then
		printf "Possibly fake VOMS extensions. Regenerating... "
		voms-proxy-init -voms vo.org -key "$X509_USER_KEY" -cert "$X509_USER_CERT" | sed "s/\$/$lf/"
	fi

	# The .lsc files are written by setup.sh, from the certificate chains of the
	# servers named in /etc/vomses: configuring the testbed, not measuring it, and
	# it needs no decision that belongs to a test run. What is measured here is what
	# the server makes of them once they are there.
	printf "Checking that .lsc files are to be found"
	lsc_files=`ls /etc/grid-security/vomsdir/*/*.lsc 2> /dev/null`
	if [ -z "$lsc_files" ]; then
		test_skipped
		print_error "none in /etc/grid-security/vomsdir - run setup.sh, which writes them from /etc/vomses"
	else
		echo "$lsc_files" | sed "s/\$/$lf/"
		test_done

		GRST_CRED_2=`curl --cert "$X509_USER_PROXY" --key "$X509_USER_PROXY" --capath "$GS_CAPATH" --cacert "$X509_USER_PROXY" --silent https://$GS_SERVER/test.cgi|grep GRST_CRED_2`

		if [ "$GRST_CRED_2" = "" ]; then
			print_error "GRST_CRED_2 not returned"
			test_failed
		else
			test_done

			printf "Checking for presence of FQAN... "
			echo "$GRST_CRED_2" | grep "$FQAN" > /dev/null
			if [ $? = 0 ]; then
				test_done
			else
				print_error "returned: $GRST_CRED_2"
				test_failed
			fi
		fi

		printf "Test listing of VOMS attributes (Regression test for bug #92077)\n"

		printf "Getting list of Role attributes from voms-proxy-info... "
		voms-proxy-info -all | grep -E "^attribute[ \t]+:" | grep "Role=" | sed -r 's/^attribute[ \t]+:[ \t]*//' > info-roles.$$.out

		if [ ! -s info-roles.$$.out ]; then
			printf "EMPTY!"
			test_skipped
		else
			test_done
			printf "Getting list of Role attributes from test.cgi... "

			curl --cert "$X509_USER_CERT" --key "$X509_USER_KEY" --capath "$GS_CAPATH" --cacert "$X509_USER_PROXY" --silent https://$GS_SERVER/test.cgi|grep -E "^GRST_CRED_AURI_.*Role=" | sed -r 's/^GRST_CRED_AURI_[0-9]+=fqan://' > test-roles-pre.$$.out

			# The file just fetched from test.cgi. This tested info-roles.$$.out
			# again - the one that was proved non-empty a few lines above - so the
			# failure it describes could never be reported.
			if [ ! -s test-roles-pre.$$.out ]; then
				printf "EMPTY!"
				test_failed
				print_error "No role attributes found, even before re-running init"
                	else
				test_done
				printf "re-running voms extensions... "
				voms-proxy-init -noregen > /dev/null 2> /dev/null
				test_done
				printf "Getting another set of Role attributes from test.cgi... "
				curl --cert "$X509_USER_PROXY" --key "$X509_USER_PROXY" --capath "$GS_CAPATH" --cacert "$X509_USER_PROXY" --silent https://$GS_SERVER/test.cgi|grep -E "^GRST_CRED_AURI_.*Role=" | sed -r 's/^GRST_CRED_AURI_[0-9]+=fqan://' > test-roles-post.$$.out
				if [ ! -s test-roles-post.$$.out ]; then
					test_failed
					print_error "List of role attributes is empty!"
				else
					test_done
					printf "Comparing attributes... "
					diff --ignore-case test-roles-pre.$$.out test-roles-post.$$.out > /dev/null
					if [ $? -eq 0 ]; then
						test_done
					else
						sort test-roles-pre.$$.out > test-roles-pre.$$.out.sorted
						sort test-roles-post.$$.out > test-roles-post.$$.out.sorted
						diff --ignore-case test-roles-pre.$$.out.sorted test-roles-post.$$.out.sorted > /dev/null
						if [ $? -eq 0 ]; then
							printf "Matching, but out of order!"
							test_warning
						else
							# test_error is not one of the status verbs; calling it
							# printed nothing but a shell error and left the report line
							# without a verdict, which is how a mismatch escaped notice.
							test_failed
							print_error "A non-matching set of role attributes has been returned"
						fi
					fi
				fi
			fi
		fi

		rm info-roles.$$.out test-roles-pre.$$.out* test-roles-post.$$.out*
	# end of "there were .lsc files"
	fi
	# end of "there is a proxy certificate"
	fi

	printf "Test flavours and sonames\n"
	for prefix in /usr /opt/glite; do
		for libdir in 'lib64' 'lib'; do
			if test -f $prefix/$libdir/libgridsite.so.*.*.*; then
				path="$prefix/$libdir"
			fi
		done
	done
	for flavour in '' '_nossl' '_globus'; do
		if test -f $path/libgridsite$flavour.so.*.*.*; then
			printf "  flavour '$flavour' $path/libgridsite$flavour.so "
			readelf -a $path/libgridsite$flavour.so.*.*.* | grep -i soname | grep libgridsite$flavour\.so\. >/dev/null
			if test $? = 0; then
				test_done
			else
				print_error "bad soname"
				test_failed
			fi
		fi
	done

	printf "Check interpretable DEFVERSION... "
	file=`find /usr/share/doc/*gridsite* -name VERSION 2>/dev/null | head -n 1`
	file2=/usr/include/gridsite.h
	if test -n "$file"; then
		DEFVERSION=`cat $file | grep "^DEFVERSION" | head -n 1 | sed 's/DEFVERSION[ \t]*=[ \t]*//'`
	elif test -f "$file2"; then
		DEFVERSION=`cat $file2 | grep "^#define[ \t]*GRST_VERSION" | sed 's/.*GRST_VERSION[ \t]*//'`
	fi
	printf "Oct %o, Hex %x" $DEFVERSION $DEFVERSION
	if [ $? -eq 0 ]; then
		test_done
	else
		test_failed
		print_error "Failed to interpret DEFVERSION as a number"
	fi

test_end
} 
#} &> $logfile

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK

