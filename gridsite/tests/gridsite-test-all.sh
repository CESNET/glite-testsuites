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
Script for testing gridsite functions

Prerequisities:
   - GridSite and httpd with mod_ssl installe

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
COMMON=gridsite-common.sh
if [ ! -r ${COMMON} ]; then
	printf "Common definitions '${COMMON}' missing!"
	exit 2
fi
source ${COMMON}

logfile=$$.tmp
flag=0
NL=""
while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		"-o" | "--output") shift ; logfile=$1 flag=1 ;;
		"-t" | "--text")  setOutputASCII ;;
		"-c" | "--color") setOutputColor ;;
		"-x" | "--html")  setOutputHTML ; NL="<BR>";;
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
check_binaries curl rm chown openssl htcp htls htmv htcp htrm htls htls htproxydestroy awk sed openssl tail head
if [ $? -gt 0 ]; then
	test_failed
else
	test_done
fi


	if [ ! -e /var/www/htdocs ]; then
		mkdir /var/www/htdocs
	fi

	printf "READ (Read Permissions)\n"

cat >/var/www/htdocs/test.html <<EOF
<html><body><h1>Hello Grid</h1></body></html>
EOF

	$SYS_RM /var/www/htdocs/.gacl

	printf "Plain read... "
	code=`curl --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates --output /dev/null --silent --write-out '%{http_code}\n'  https://$(hostname -f)/test.html`
	printf "Return code $code"
	if [ "$code" = "403" ]; then 
		test_done
	else
		test_failed
	fi

cat >/var/www/htdocs/.gacl <<EOF
<gacl>
  <entry>
    <any-user/>
      <allow><read/></allow>
  </entry>
</gacl>
EOF


	printf "With gacl... "
	code=`curl --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates --output /dev/null --silent --write-out '%{http_code}\n'  https://$(hostname -f)/test.html`
	printf "Return code $code"
	if [ "$code" = "200" ]; then 
		test_done
	else
		test_failed
	fi


	printf "Get index (list & read permissions)\n"

	printf "Plain read... "
	code=`curl --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates --output /dev/null --silent --write-out '%{http_code}\n' https://$(hostname -f)/`
	printf "Return code $code"
	if [ "$code" = "403" ]; then 
		test_done
	else
		test_failed
	fi

cat >/var/www/htdocs/.gacl <<EOF
<gacl>
  <entry>
    <person>
      <dn>`openssl x509 -noout -subject -in /etc/grid-security/hostcert.pem | sed -e 's/^subject= //'`</dn>
    </person>
    <allow><read/><list/></allow>
  </entry>
</gacl>
EOF

	printf "With gacl... "
	code=`curl --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates --output /dev/null --silent --write-out '%{http_code}\n' \
https://$(hostname -f)/`
	printf "Return code $code"
	if [ "$code" = "200" ]; then 
		test_done
	else
		test_failed
	fi




	printf "WRITE & DELETE (write permissions)\n"

	rm -f /var/www/htdocs/.gacl /var/www/htdocs/test.txt
	date > /tmp/test.txt
	chown apache /var/www/htdocs/

	printf "Plain write... "
	code=`curl --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates --output /dev/null --silent --write-out '%{http_code}\n' --upload-file /tmp/test.txt https://$(hostname -f)/test.txt`
	printf "Return code $code"
	if [ "$code" = "403" ]; then 
		test_done
	else
		test_failed
	fi

cat >/var/www/htdocs/.gacl <<EOF
<gacl>
  <entry>
    <person>
      <dn>`openssl x509 -noout -subject -in /etc/grid-security/hostcert.pem | sed -e 's/^subject= //'`</dn>
    </person>
    <allow><write/></allow>
  </entry>
</gacl>
EOF

	printf "With gacl... "
	code=`curl --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates --output /dev/null --silent --write-out '%{http_code}\n' --upload-file /tmp/test.txt https://$(hostname -f)/test.txt`
	cmp -s /tmp/test.txt /var/www/htdocs/test.txt
	printf "Return code $code"
	if [ $? -eq 0 -a "$code" = "201" ]; then 
		test_done
	else
		test_failed
	fi

	printf "Try deletion... "
	mv  /var/www/htdocs/.gacl /var/www/htdocs/.gacl.bak
	code=`curl --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates --output /dev/null --silent --write-out '%{http_code}\n' -X DELETE https://$(hostname -f)/test.txt`
	printf "Return code $code"
	if [ $? -eq 0 -a "$code" = "403" ]; then 
		test_done
	else
		test_failed
	fi

	mv /var/www/htdocs/.gacl.bak /var/www/htdocs/.gacl

	printf "With gacl... "
	code=`curl --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates --output /dev/null --silent --write-out '%{http_code}\n' -X DELETE https://$(hostname -f)/test.txt`
	printf "Return code $code"
	if [ $? -eq 0 -a "$code" = "200" ]; then 
		test_done
	else
		test_failed
	fi
	chown root /var/www/htdocs


	printf "Checking attributes passed on to the environment\n"

cat >/var/www/htdocs/.gacl <<EOF
<gacl>
  <entry>
    <person>
      <dn>`openssl x509 -noout -subject -in /etc/grid-security/hostcert.pem | sed -e 's/^subject= //'`</dn>
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

	
	printf "Run test.cgi... "
	chmod +x /var/www/htdocs/test.cgi
	code=`curl --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates --output /tmp/gridsite.log --silent --write-out '%{http_code}\n'  https://$(hostname -f)/test.cgi`
	printf "Return code $code"
	if [ "$code" = "200" ]; then 
		test_done
	else
		test_failed
	fi
	printf "Check for GRST_* veriables... "
grep "^GRST_" /tmp/gridsite.log >/dev/null 2>/dev/null
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi


	printf "Test the basic commands (htcp, htls, htmkdir, htmv, htrm)\n"

cat >/var/www/htdocs/.gacl <<EOF
<gacl>
  <entry>
    <person>
      <dn>`openssl x509 -noout -subject -in /etc/grid-security/hostcert.pem | sed -e 's/^subject= //'`</dn>
    </person>
    <allow><read/><write/><list/></allow>
  </entry>
</gacl>
EOF

	chown apache /var/www/htdocs/

	date > /tmp/test.txt

	printf "Testing htcp... "
	htcp --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates/ /tmp/test.txt https://$(hostname -f)/
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi
	printf "Checking by htls... "
	htls --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates/ https://$(hostname -f)/test.txt > /dev/null
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi
	printf "Testing htmv... "
	htmv --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates/ https://$(hostname -f)/test.txt https://$(hostname -f)/test2.txt
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi
	printf "htcp, file 2... "
	htcp --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates/ https://$(hostname -f)/test2.txt /tmp
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi
	printf "Testing htrm... "
	htrm --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates/ https://$(hostname -f)/test2.txt
	if [ $? -eq 0 ]; then 
		test_done
	else
		test_failed
	fi
	printf "Checking by htls... "
	htls --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates/ https://$(hostname -f)/test2.txt 2> /dev/null
	if [ $? -eq 22 ]; then 
		test_done
	else
		test_failed
	fi
	printf "Checking directory contents with htls... "
	htls --cert /etc/grid-security/hostcert.pem --key /etc/grid-security/hostkey.pem --capath /etc/grid-security/certificates/ https://$(hostname -f)/ > /dev/null
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

	chown root /var/www/htdocs/

	printf "Test proxy delegation\n"

	if [ ! -e /var/www/proxycache ]; then
		mkdir /var/www/proxycache
	fi
	chown apache /var/www/proxycache

	#delegation
	id=`htproxyput --cert /tmp/x509up_u0 --key /tmp/x509up_u0 --capath /etc/grid-security/certificates https://$(hostname -f)/gridsite-delegation.cgi`
	printf "id: $id"
	if [ $? -eq 0 -a -n "$id" ]; then 
		test_done
	else
		test_failed
	fi

	expiry=`htproxyunixtime --cert /tmp/x509up_u0 --key /tmp/x509up_u0 --capath /etc/grid-security/certificates --delegation-id $id https://$(hostname -f)/gridsite-delegation.cgi`

	newid=`htproxyrenew --cert /tmp/x509up_u0 --key /tmp/x509up_u0 --capath /etc/grid-security/certificates --delegation-id $id https://$(hostname -f)/gridsite-delegation.cgi`
	printf "newid: $newid"
	if [ $? -eq 0 -a -n "$newid" ]; then 
		test_done
	else
		test_failed
	fi

	htproxydestroy --cert /tmp/x509up_u0 --key /tmp/x509up_u0 --capath /etc/grid-security/certificates --delegation-id $id https://$(hostname -f)/gridsite-delegation.cgi


	printf "Test handling of VOMS .lsc files (Regression test for bug #39254 and #82023)\n"

	if [ -e /tmp/x509up_u`id -u` ]; then
	
		# Add read permissions for any user to .gacl	
		sed -i 's/<\/gacl>/<entry><any-user\/><allow><read\/><\/allow><\/entry><\/gacl>/' /var/www/htdocs/.gacl
	
		FQAN=`voms-proxy-info --fqan`

		mkdir -p /tmp/vomsdir.$$
		mv -f /etc/grid-security/vomsdir/* /tmp/vomsdir.$$/
		printf "Trying with empty vomsdir. GRST_CRED_2 should not be present... "
		GRST_CRED_2=`curl --cert /tmp/x509up_u0 --key /tmp/x509up_u0 --capath /etc/grid-security/certificates --silent https://$(hostname -f)/test.cgi|grep GRST_CRED_2`
		if [ "$GRST_CRED_2" = "" ]; then
			test_done
		else
			print_error "returned: $GRST_CRED_2\n"
			test_failed
		fi
		mv -f /tmp/vomsdir.$$/* /etc/grid-security/vomsdir/
		rm -rf /tmp/vomsdir.$$ 

		printf "Setting up .lsc file and trying again\n"

		UTOPIA=`voms-proxy-info -all | grep -A 100 "extension information" | grep "^issuer" | grep "L=Tropic" | grep "O=Utopia" | grep "OU=Relaxation"`
		if [ "$UTOPIA" != "" ]; then
			printf "Possibly fake VOMS extensions. Regenerating... "
#			voms-proxy-info -all | grep -A 100 "extension information" | sed "s/\$/$NL/"
			voms-proxy-init -voms vo.org -key $x509_USER_KEY -cert $x509_USER_CERT | sed "s/\$/$NL/"
		fi;
#		voms-proxy-info -all | grep -A 100 "extension information" | sed "s/\$/$NL/"

		for vomsfile in /etc/vomses/*
		do
			if [ -f $vomsfile ]; then
				VOMSHOSTONLY=`cat $vomsfile | awk '{ print $2 }' | sed 's/"//g'`
				VONAME=`cat $vomsfile | awk '{ print $1 }' | sed 's/"//g'`
#				if [ ! -f /etc/grid-security/vomsdir/$VONAME/$VOMSHOSTONLY.lsc ]; then
					VOMSHOST=`cat $vomsfile | awk '{ print $2 ":" $3; }' | sed 's/"//g'`
					openssl s_client -connect $VOMSHOST 2>&1 | grep "^depth" | sed 's/^depth=//' | sort -r -n > $VOMSHOSTONLY.$$.DNs.txt
					VOMSCERT=`tail -n 1 $VOMSHOSTONLY.$$.DNs.txt | sed -r 's/^[0-9]+\s+//'`
					VOMSCA=`grep -E "^1[ \t]" $VOMSHOSTONLY.$$.DNs.txt | sed -r 's/^[0-9]+\s+//'`

					mkdir -p /etc/grid-security/vomsdir/$VONAME
					printf "$VOMSCERT\n$VOMSCA\n" > /etc/grid-security/vomsdir/$VONAME/$VOMSHOSTONLY.lsc

					printf "Generated /etc/grid-security/vomsdir/$VONAME/$VOMSHOSTONLY.lsc\n$NL"

					rm $VOMSHOSTONLY.$$.DNs.txt
#				else
#					printf "/etc/grid-security/vomsdir/$VONAME/$VOMSHOSTONLY.lsc already exists\n$NL"
#				fi

#				cat /etc/grid-security/vomsdir/$VONAME/$VOMSHOSTONLY.lsc | sed "s/\$/$NL/"
			fi
		done

		GRST_CRED_2=`curl --cert /tmp/x509up_u0 --key /tmp/x509up_u0 --capath /etc/grid-security/certificates --silent https://$(hostname -f)/test.cgi|grep GRST_CRED_2`

		if [ "$GRST_CRED_2" = "" ]; then
			print_error "GRST_CRED_2 not returned"
			test_failed
		else
			test_done

			printf "Checking for presence of FQAN... "
			echo "$GRST_CRED_2" | grep $FQAN > /dev/null
			if [ $? = 0 ]; then
				test_done
			else
				print_error "returned: $GRST_CRED_2"
				test_failed
			fi
		fi

		printf "Test listing of VOMS attributes (Regression test for bug #92077)\n"
		GRST_CRED_AURI=`curl --cert /tmp/x509up_u0 --key /tmp/x509up_u0 --capath /etc/grid-security/certificates --silent https://$(hostname -f)/test.cgi|grep -E GRST_CRED_AURI.*Testers`
		if [ "$GRST_CRED_AURI" = "" ]; then
			test_failed
			print_error "attribute not present"
		else 
			printf " $GRST_CRED_AURI"
			test_done
		fi

	else
		printf "No proxy certificate"
		test_skipped
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
		printf "  flavour '$flavour' "
		if test -f $path/libgridsite$flavour.so.*.*.*; then
			printf "$path/libgridsite$flavour.so "
			readelf -a $path/libgridsite$flavour.so.*.*.* | grep -i soname | grep libgridsite$flavour\.so\. >/dev/null
			if test $? = 0; then
				test_done
			else
				print_error "bad soname"
				test_failed
			fi
		else
			print_error "not present"
			test_failed
		fi
	done

test_end
} 
#} &> $logfile

#if [ $flag -ne 1 ]; then
# 	cat $logfile
# 	$SYS_RM $logfile
#fi
exit $TEST_OK

