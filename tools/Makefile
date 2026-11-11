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
#   HOURS   lifetime of the published proxies, in hours (default 168). Tests
#           that watch a proxy being renewed want a short one, e.g. HOURS=2
#   EXTRA   number of additional client certificates trusted_client01.., for
#           tests that act as somebody else than the tester     (default 1)
#   PROXY   where the VOMS proxy of the first VO is copied; the default is the
#           location GSI tools fall back to when X509_USER_PROXY is unset
#   DESTDIR installation root for 'install'            (default empty)
#   GENFLAGS extra flags for the generator, e.g. GENFLAGS=--fresh-ca

CERTS      ?= /tmp/certs
VOS        ?= vo.org
HOURS      ?= 168
EXTRA      ?= 1
DESTDIR    ?=
PROXY      ?= /tmp/x509up_u$(shell id -u)
GENFLAGS   ?=

GEN      := ./generate-test-certs.sh
GS       := $(CERTS)/grid-security
# One --voms per VO.
VOMSFLAGS = $(foreach vo,$(VOS),--voms $(vo))
# The proxy that gets published is the one faked for the first VO.
VO0       = $(firstword $(VOS))
EXTRAFLAG   = --extra $(EXTRA)

.DEFAULT_GOAL := all
.PHONY: all certs proxy install clean help

all: proxy

# Generation always re-runs. That is cheap and safe: the script reuses
# $(CERTS)/trusted-ca/ unless GENFLAGS carries --fresh-ca, and it re-issues every
# leaf certificate either way, so no certificate signed by a replaced CA can
# survive a re-run.
certs:
	$(GEN) $(strip $(VOMSFLAGS) --hours $(HOURS) $(EXTRAFLAG) $(GENFLAGS)) $(CERTS)

# Only the tester's own proxy is published, because that one has a conventional
# location that GSI tools fall back to. The additional identities stay in the
# tree: a test that acts as one of them names its file explicitly. Changing
# HOURS means re-running the generator, which 'proxy' does through its
# prerequisite.
proxy: certs
	@test -r $(CERTS)/home/voms-$(VO0).pem \
		|| { echo "no $(CERTS)/home/voms-$(VO0).pem - is VOS set correctly?"; exit 1; }
	cp -f $(CERTS)/home/voms-$(VO0).pem $(PROXY)
	chmod 600 $(PROXY)
	@echo "proxy: $(PROXY)"
ifneq ($(strip $(EXTRA)),)
ifneq ($(strip $(EXTRA)),0)
	@echo "additional identities are in $(CERTS)/home/ as voms-<VO>-clientNN.pem; they"
	@echo "are used through X509_USER_PROXY, so they need no conventional location"
endif
endif
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
