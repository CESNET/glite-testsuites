# Driver for generate-test-certs.sh.
#
#   make                        generate the tree and publish a VOMS proxy
#   make install DESTDIR=/tmp/d install the trust anchors under $(DESTDIR)/etc
#   make help                   list targets and variables
#
# Variables (all overridable on the command line):
#
#   CERTS   target directory for the generated tree   (default /tmp/certs)
#   VOS     VOs to fake attributes for, space separated (default vo.org)
#   PROXY   where the VOMS proxy of the first VO is copied; the default is the
#           location GSI tools fall back to when X509_USER_PROXY is unset
#   DESTDIR installation root for 'install'            (default empty)
#   GENFLAGS extra flags for the generator, e.g. GENFLAGS=--fresh-ca

CERTS    ?= /tmp/certs
VOS      ?= vo.org
DESTDIR  ?=
PROXY    ?= /tmp/x509up_u$(shell id -u)
GENFLAGS ?=

GEN      := ./generate-test-certs.sh
GS       := $(CERTS)/grid-security
# One --voms per VO.
VOMSFLAGS = $(foreach vo,$(VOS),--voms $(vo))
# The proxy that gets published is the one faked for the first VO.
VO0       = $(firstword $(VOS))

.DEFAULT_GOAL := all
.PHONY: all certs proxy install clean help

all: proxy

# Generation always re-runs. That is cheap and safe: the script reuses
# $(CERTS)/trusted-ca/ unless GENFLAGS carries --fresh-ca, and it re-issues every
# leaf certificate either way, so no certificate signed by a replaced CA can
# survive a re-run.
certs:
	$(GEN) $(strip $(VOMSFLAGS) $(GENFLAGS)) $(CERTS)

proxy: certs
	@test -r $(CERTS)/home/voms-$(VO0).pem \
		|| { echo "no $(CERTS)/home/voms-$(VO0).pem - is VOS set correctly?"; exit 1; }
	cp -f $(CERTS)/home/voms-$(VO0).pem $(PROXY)
	chmod 600 $(PROXY)
	@echo "proxy: $(PROXY)"
	@echo "GSI tools pick this up with no X509_USER_PROXY: source $(CERTS)/env.sh && voms-proxy-info --all"

# Installs the CA trust anchors, the CRLs, the signing policy and namespace
# files, the vomsdir trust files, and the host certificate. Nothing under
# $(DESTDIR)/etc/grid-security is deleted, so existing IGTF CAs survive; files
# with the same name are overwritten. The CA private key lives in
# $(CERTS)/trusted-ca/ and is deliberately not installed.
install:
	@test -d $(GS)/certificates \
		|| { echo "$(GS)/certificates is missing - run 'make certs' first"; exit 1; }
	install -d $(DESTDIR)/etc/grid-security/certificates
	cp -a $(GS)/certificates/. $(DESTDIR)/etc/grid-security/certificates/
	install -m 644 $(GS)/hostcert.pem $(DESTDIR)/etc/grid-security/hostcert.pem
	install -m 600 $(GS)/hostkey.pem  $(DESTDIR)/etc/grid-security/hostkey.pem
	@if [ -d $(GS)/vomsdir ]; then \
		install -d $(DESTDIR)/etc/grid-security/vomsdir; \
		cp -a $(GS)/vomsdir/. $(DESTDIR)/etc/grid-security/vomsdir/; \
	fi
	@echo "installed into $(DESTDIR)/etc/grid-security"

clean:
	rm -rf $(CERTS)
	@echo "removed $(CERTS) (the published proxy at $(PROXY) is left alone)"

# Prints the comment block at the top of this file.
help:
	@awk '/^#/{sub(/^# ?/,"");print;next} {exit}' Makefile
