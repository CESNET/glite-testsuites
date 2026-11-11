#!/bin/bash
#
# Simplified, modern-OpenSSL replacement for bin/generate-test-certificates.sh.
#
# Creates a throwaway test CA and the handful of certificates that were actually
# used out of the full generator's "trusted" set:
#
#   trusted-certs/trusted_client00.{cert,priv}      SHA-256, CN=$LOGNAME
#   trusted-certs/trusted_clientsha512.{cert,priv}  SHA-512, fixed CN
#   grid-security/hostcert.pem|hostkey.pem          CN=<fully qualified hostname>
#   grid-security/certificates/<hash>.{0,r0,signing_policy,namespaces}
#   home/usercert.pem|userkey.pem
#   home/voms-<VO>.pem, grid-security/vomsdir/<VO>/<host>.lsc      with --voms <VO>
#   env.sh
#
# Where this differs from the old generator, and why:
#
#   * The CA is created here rather than copied out of test/: the checked-in CAs
#     are 1024-bit RSA with SHA-1 signatures (MD5 for subsubca) and expired
#     2025-10-08, so nothing they sign verifies any more.
#   * Everything is signed with SHA-2. Signing with SHA-1 or MD5 fails outright
#     on crypto-policies systems (__openssl_block_sha1_signatures = 1) with
#     "do_sigver_init:invalid digest".
#   * The CA DN, the leaf DNs, and the on-disk layout are unchanged from the old
#     generator, so grid-mapfile entries and grid-security/vomsdir/*.lsc files that pin these
#     DNs keep matching. Only the CA key material is new.
#   * No proxies, PKCS#12 keystores, or the bad/fake/big/expired/nokeyusage/
#     subsubca/slash CA variants. VOMS attributes are faked with
#     voms-proxy-fake only when --voms is given, as it needs a host certificate
#     to sign the attribute certificate with.
#   * Keys are written unencrypted, as the old grid-security/ and home/ copies
#     were, and chmod 400 because Globus refuses to use world-readable keys.
#
# The CA is reused if <target>/trusted-ca/trusted.cert already exists, so
# re-running into the same directory keeps one stable chain; --fresh-ca replaces
# it. All leaf certificates are re-issued on every run.

set -euo pipefail

BASE_DN='/C=UG/L=Tropic/O=Utopia/OU=Relaxation'
CA_CN='the trusted CA'
CA_DN="$BASE_DN/CN=$CA_CN"
CA_DIR=trusted-ca
CERT_DIR=trusted-certs

DAYS=1500
BITS=3072
FRESH_CA=no
TARGETDIR=''
# Space separated list of VOs to fake VOMS attributes for; empty means no VOMS.
VO_LIST=''
HOST_CN=''
# Only used as the host part of the AC URI and the vomsdir file name, so it has
# to be the exact name consumers will look the VOMS server up under.
VOMS_PORT=15000
# AC and proxy lifetime of the fake VOMS proxies, in hours.
VOMS_HOURS=168

usage() {
	echo "usage: $0 [--fresh-ca] [--days N] [--bits N] [--host-cn NAME]"
	echo "          [--voms VO]... target_dir"
	echo
	echo "  --fresh-ca      replace an existing CA in target_dir instead of reusing it"
	echo "  --days N        validity of the CA and of every certificate (default $DAYS)"
	echo "  --bits N        RSA key size (default $BITS)"
	echo "  --host-cn NAME  CN of the host certificate (default: the fully qualified"
	echo "                  hostname), also used as the fake VOMS server name"
	echo "  --voms VO       fake a VOMS attribute for VO, repeatable; needs"
	echo "                  voms-proxy-fake"
	echo
	echo "The user certificate CN comes from \$LOGNAME (falling back to whoami)."
}

while [ $# -gt 0 ]; do
	case "$1" in
	--fresh-ca | -f)
		FRESH_CA=yes
		shift
		;;
	--voms)
		[ $# -ge 2 ] || {
			echo "--voms needs a VO name" >&2
			exit 1
		}
		VO_LIST="$VO_LIST $2"
		shift 2
		;;
	--host-cn)
		[ $# -ge 2 ] || {
			echo "--host-cn needs a value" >&2
			exit 1
		}
		HOST_CN=$2
		shift 2
		;;
	--days)
		[ $# -ge 2 ] || {
			echo "--days needs a value" >&2
			exit 1
		}
		DAYS=$2
		shift 2
		;;
	--bits)
		[ $# -ge 2 ] || {
			echo "--bits needs a value" >&2
			exit 1
		}
		BITS=$2
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	-*)
		echo "unknown option: $1" >&2
		usage >&2
		exit 1
		;;
	*)
		[ -z "$TARGETDIR" ] || {
			echo "target_dir given twice" >&2
			exit 1
		}
		TARGETDIR=$1
		shift
		;;
	esac
done

[ -n "$TARGETDIR" ] || {
	usage >&2
	exit 1
}

mkdir -p "$TARGETDIR"
cd "$TARGETDIR"
TARGETDIR=$PWD

# The user's login name is the CN of the client certificate, as before.
USER_CN=${LOGNAME:-$(whoami 2>/dev/null || true)}
[ -n "$USER_CN" ] || {
	echo "cannot determine a user name: set LOGNAME" >&2
	exit 1
}

# Fully qualified hostname, as before: hostname -A can return several aliases
# (or an empty string with a zero exit status on some builds), so take the first
# word and fall back to hostname -f. --host-cn overrides it.
if [ -z "$HOST_CN" ]; then
	HOST_CN=$(hostname -A 2>/dev/null | awk '{print $1}') || HOST_CN=''
	[ -n "$HOST_CN" ] || HOST_CN=$(hostname -f 2>/dev/null || true)
	[ -n "$HOST_CN" ] || {
		echo "cannot determine the fully qualified hostname" >&2
		exit 1
	}
fi
# The CN goes into a slash-separated DN and into the vomsdir file name, so
# characters that would need DN escaping cannot be tolerated.
if [ -z "$HOST_CN" ] || printf %s "$HOST_CN" | LC_ALL=C grep -q '[/,=+;]'; then
	echo "host CN '$HOST_CN' contains characters this script cannot escape" >&2
	exit 1
fi

echo "target directory: $TARGETDIR"
echo "openssl:          $(openssl version)"
echo "user certificate CN: $USER_CN"
echo "host certificate CN: $HOST_CN"

# ---------------------------------------------------------------- openssl config
# Written into the CA directory, with paths relative to this directory, so that
# inspecting or re-running an openssl ca command by hand works the same way.
mkdir -p "$CA_DIR/newcerts"
cat >"$CA_DIR/req_conf.cnf" <<'EOF'
[ req ]
distinguished_name  = req_distinguished_name
string_mask         = utf8only

[ req_distinguished_name ]

#### CA database and signing

[ ca ]
default_ca          = CA_default

[ CA_default ]
dir                 = trusted-ca
database            = $dir/index.txt
new_certs_dir       = $dir/newcerts
serial              = $dir/serial
certificate         = $dir/trusted.cert
private_key         = $dir/trusted.priv
default_md          = sha256
default_days        = 1500
policy              = policy_any
unique_subject      = no

[policy_any]
countryName             = supplied
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional
userId                  = optional
serialNumber            = optional

#### extension sections

[ ca_cert ]
basicConstraints        = critical, CA:true
keyUsage                = critical, cRLSign, keyCertSign
subjectKeyIdentifier    = hash

[ ca_client ]
basicConstraints        = CA:false
keyUsage                = critical, nonRepudiation, digitalSignature, keyEncipherment
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always
# For normal client use this is typical
nsCertType              = client, email
nsComment               = "OpenSSL Generated Client Certificate"

[ ca_server ]
basicConstraints        = CA:false
keyUsage                = critical, nonRepudiation, digitalSignature, keyEncipherment
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always
# This is OK for an SSL server.
nsCertType              = server
nsComment               = "OpenSSL Generated Server Certificate"
EOF

# ------------------------------------------------------------------- CA creation

if [ "$FRESH_CA" = yes ] || [ ! -r "$CA_DIR/trusted.cert" ]; then
	echo "creating a new CA in $CA_DIR/"
	rm -f "$CA_DIR/trusted.cert" "$CA_DIR/trusted.priv" "$CA_DIR/trusted.crl" \
		"$CA_DIR/index.txt" "$CA_DIR/index.txt.attr" "$CA_DIR/serial"
	rm -rf "$CA_DIR/newcerts"
	mkdir -p "$CA_DIR/newcerts"

	openssl genrsa -out "$CA_DIR/trusted.priv" "$BITS" 2>/dev/null
	chmod 400 "$CA_DIR/trusted.priv"
	# Self-signed, so no CA database is needed for this one.
	openssl req -new -x509 -sha256 -days "$DAYS" \
		-key "$CA_DIR/trusted.priv" -out "$CA_DIR/trusted.cert" \
		-config "$CA_DIR/req_conf.cnf" -extensions ca_cert -subj "$CA_DN"

	: >"$CA_DIR/index.txt"
	echo 1000 >"$CA_DIR/serial"
else
	echo "reusing the existing CA in $CA_DIR/ (--fresh-ca to replace it)"
fi

# ------------------------------------------------------------- certificate issue

# issue_cert <file base> <CN> <extension section> <digest>
issue_cert() {
	local filebase=$1 cn=$2 ext=$3 digest=$4

	# Replace any certificate from an earlier run: leaving one signed by a
	# replaced CA behind would silently break the chain.
	rm -f "$filebase.cert" "$filebase.priv"

	openssl genrsa -out "$filebase.priv" "$BITS" 2>/dev/null
	chmod 400 "$filebase.priv"
	openssl req -new -key "$filebase.priv" -out "$filebase.req" \
		-config "$CA_DIR/req_conf.cnf" -subj "$BASE_DN/CN=$cn"
	openssl ca -in "$filebase.req" -out "$filebase.cert" -notext -batch \
		-preserveDN -extensions "$ext" -md "$digest" -days "$DAYS" \
		-config "$CA_DIR/req_conf.cnf"
	rm -f "$filebase.req"
	echo "issued $filebase.cert (CN=$cn, $digest)"
}

mkdir -p "$CERT_DIR" home grid-security/certificates

issue_cert "$CERT_DIR/trusted_client00" "$USER_CN" ca_client sha256
issue_cert "$CERT_DIR/trusted_clientsha512" "trusted client with sha512 hash" ca_client sha512
issue_cert "$CERT_DIR/trusted_host" "$HOST_CN" ca_server sha256

cp -f "$CERT_DIR/trusted_client00.cert" home/usercert.pem
cp -f "$CERT_DIR/trusted_client00.priv" home/userkey.pem
chmod 400 home/userkey.pem
cp -f "$CERT_DIR/trusted_host.cert" grid-security/hostcert.pem
cp -f "$CERT_DIR/trusted_host.priv" grid-security/hostkey.pem
chmod 400 grid-security/hostkey.pem

# ------------------------------------------------------------------------- CRL

openssl ca -gencrl -crldays "$DAYS" -md sha256 -out "$CA_DIR/trusted.crl" \
	-config "$CA_DIR/req_conf.cnf"

# ------------------------------------------------------- GSI trust anchor files

# Globus looks CA files up by an MD5-based "old" subject hash, while current
# OpenSSL (openssl verify -CApath, s_client -CApath) uses the SHA-1 based one,
# so install the files under both.
write_ca_files() {
	local hash=$1
	cp -f "$CA_DIR/trusted.cert" "grid-security/certificates/${hash}.0"
	cp -f "$CA_DIR/trusted.crl" "grid-security/certificates/${hash}.r0"

	# The DN is built from the variables above rather than parsed back out of
	# 'openssl x509 -subject', whose output format changed in OpenSSL 1.1.
	cat >"grid-security/certificates/${hash}.signing_policy" <<EOF
# Signing policy file for $CA_CN
access_id_CA            X509    '$CA_DN'
pos_rights              globus  CA:sign
cond_subjects           globus  '"$BASE_DN/*"'
EOF

	cat >"grid-security/certificates/${hash}.namespaces" <<EOF
#NAMESPACES-VERSION: 1.0
# Namespaces file for $CA_CN
TO Issuer "$CA_DN" \\
	PERMIT Subject "$BASE_DN/.*"
EOF
}

hash_old=$(openssl x509 -in "$CA_DIR/trusted.cert" -noout -subject_hash_old)
hash_new=$(openssl x509 -in "$CA_DIR/trusted.cert" -noout -subject_hash)
write_ca_files "$hash_old"
[ "$hash_old" = "$hash_new" ] || write_ca_files "$hash_new"
echo "CA installed as $hash_old.0 (old hash) and $hash_new.0 (new hash)"

# --------------------------------------------------------------- fake VOMS ACs
# voms-proxy-fake signs the attribute certificate with the host certificate, and
# the client then looks the signing host up in $X509_VOMS_DIR. Three things have
# to line up, or voms-proxy-info reports "Cannot verify AC signature":
#
#   * the AC must carry a URI, so pass -uri: without it the client has no
#     hostname to resolve ("Unable to determine hostname from AC");
#   * the trust file must be named vomsdir/<VO>/<hostname>.lsc after that URI's
#     hostname, not after the certificate file name;
#   * its DNs must be in slash form - the host certificate subject on the first
#     line and the CA that issued it on the second. Comma-separated DNs, or DNs
#     missing the C= component, do not match.

# fake_ac <VO> <source cert> <source key> <output file> <FQAN>
fake_ac() {
	local vo=$1 srccert=$2 srckey=$3 out=$4 fqan=$5 info
	rm -f "$out"
	# Both tools take the trust store from X509_CERT_DIR; voms-proxy-fake also
	# accepts -certdir, but that one is not used for every lookup.
	X509_CERT_DIR="$TARGETDIR/grid-security/certificates" \
		voms-proxy-fake -cert "$srccert" -key "$srckey" \
		-hostcert "$CERT_DIR/trusted_host.cert" -hostkey "$CERT_DIR/trusted_host.priv" \
		-uri "$HOST_CN:$VOMS_PORT" -voms "$vo" -fqan "$fqan" \
		-hours "$VOMS_HOURS" -vomslife "$VOMS_HOURS" -out "$out" -quiet
	# Reading the proxy back is the check that matters: voms-proxy-info resolves
	# the hostname from the AC and verifies the signature against the .lsc file.
	if ! info=$(X509_CERT_DIR="$TARGETDIR/grid-security/certificates" \
		X509_VOMS_DIR="$TARGETDIR/grid-security/vomsdir" \
		voms-proxy-info --file "$out" --all 2>&1) ||
		printf '%s' "$info" | grep -qi warning; then
		printf '%s\n' "$info"
		echo "VOMS: the attribute certificate in $out does not verify" >&2
		return 1
	fi
	printf '%s  %s\n' "$out" \
		"$(printf '%s' "$info" | sed -n 's/^attribute *: /attribute = /p')"
}

create_voms_acs() {
	local vo=$1
	case $vo in
	*[/]*)
		echo "VO name '$vo' must not contain a slash" >&2
		exit 1
		;;
	esac
	mkdir -p "grid-security/vomsdir/$vo"
	printf '%s\n%s\n' "$BASE_DN/CN=$HOST_CN" "$CA_DN" >"grid-security/vomsdir/$vo/${HOST_CN}.lsc"
	fake_ac "$vo" "$CERT_DIR/trusted_client00.cert" "$CERT_DIR/trusted_client00.priv" \
		"home/voms-$vo.pem" "/$vo/Role=NULL/Capability=NULL"
	fake_ac "$vo" "$CERT_DIR/trusted_clientsha512.cert" \
		"$CERT_DIR/trusted_clientsha512.priv" \
		"home/voms-$vo-sha512.pem" "/$vo/Role=NULL/Capability=NULL"
}

if [ -n "$VO_LIST" ]; then
	command -v voms-proxy-fake >/dev/null 2>&1 || {
		echo "--voms needs voms-proxy-fake on PATH" >&2
		exit 1
	}
	for vo in $VO_LIST; do
		create_voms_acs "$vo"
	done
fi

# ------------------------------------------------------------------ verification

for cert in home/usercert.pem grid-security/hostcert.pem \
	"$CERT_DIR/trusted_clientsha512.cert"; do
	openssl verify -x509_strict -crl_check \
		-CAfile "$CA_DIR/trusted.cert" -CRLfile "$CA_DIR/trusted.crl" "$cert"
	# Also prove the hashed grid-security/certificates directory is usable.
	openssl verify -crl_check -CApath grid-security/certificates "$cert"
done

# ------------------------------------------------------------- env for the user

cat >env.sh <<EOF
#!/bin/bash
export X509_CERT_DIR=$TARGETDIR/grid-security/certificates
export X509_USER_CERT=$TARGETDIR/home/usercert.pem
export X509_USER_KEY=$TARGETDIR/home/userkey.pem
EOF

echo
echo "test certificates can be used with the following environment variables:"
echo "export X509_CERT_DIR=$TARGETDIR/grid-security/certificates"
echo "export X509_USER_CERT=$TARGETDIR/home/usercert.pem"
echo "export X509_USER_KEY=$TARGETDIR/home/userkey.pem"

if [ -n "$VO_LIST" ]; then
	echo "export X509_VOMS_DIR=$TARGETDIR/grid-security/vomsdir" >>env.sh
	echo "export X509_VOMS_DIR=$TARGETDIR/grid-security/vomsdir"
fi
