#!/bin/bash
#
# Copyright (c) 2026 CESNET
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
# ------------------------------------------------------------------------------
# Hides the system VOMS trust directory and puts it back.
#
#   gridsite-vomsdir hide | restore
#
# gridsite-test-all.sh needs to see what mod_gridsite does when there are no .lsc
# files to be found, which means emptying /etc/grid-security/vomsdir for the
# duration of one check. This program exists so that the tester can be granted
# exactly that, by name, in /etc/sudoers.d, instead of a rule allowing 'sudo mv'
# with a wildcard - which would allow moving anything on the machine.
#
# It takes no paths as arguments on purpose: what it touches is fixed here, so the
# sudoers entry means what it says. It is root's program, run by sudo, and it says
# so if it is not.
#
# The saved copy lives under $STATE_DIR and survives a crash; 'restore' is
# idempotent, so a run that died with the directory hidden can simply be undone by
# running this again, and setup.sh says as much in its report.
# ------------------------------------------------------------------------------

set -u

VOMSDIR=${VOMSDIR:-/etc/grid-security/vomsdir}
STATE_DIR=${STATE_DIR:-/var/lib/glite-testsuites}
SAVED=$STATE_DIR/vomsdir-hidden

# Checked before the identity check, because a wrong argument is a wrong argument
# whoever types it - and because it is the one thing about this program that can be
# exercised without root.
case "${1:-}" in
	'hide' | 'restore') ;;
	*)
		printf 'Usage: %s hide | restore\n' "$(basename "$0")" >&2
		exit 2
	;;
esac

if [ "$(id -u)" -ne 0 ]; then
	printf '%s is installed for sudo; run it as root.\n' "$(basename "$0")" >&2
	exit 1
fi

case "${1:-}" in
	'hide')
		if [ -e "$SAVED" ]; then
			printf 'the contents of %s are already saved in %s\n' "$VOMSDIR" "$SAVED" >&2
			printf 'run "%s restore" first\n' "$(basename "$0")" >&2
			exit 1
		fi
		if [ ! -d "$VOMSDIR" ]; then
			printf 'no %s to hide\n' "$VOMSDIR" >&2
			exit 1
		fi
		install -d -m 0700 "$SAVED" || exit 1
		if ! cp -a "$VOMSDIR"/. "$SAVED"/; then
			rm -rf "$SAVED"
			printf 'could not copy %s to %s\n' "$VOMSDIR" "$SAVED" >&2
			exit 1
		fi
		# The directory stays in place and empty: mod_gridsite is expected to find
		# it, and it is the absence of the .lsc files that is being tested.
		find "$VOMSDIR" -mindepth 1 -delete || exit 1
		printf '%s hidden, %d file(s) saved in %s\n' "$VOMSDIR" "$(find "$SAVED" -type f | wc -l)" "$SAVED"
	;;
	'restore')
		if [ ! -d "$SAVED" ]; then
			# Nothing was hidden, or it is already back. A test that died part way
			# through can call this without knowing where it left off.
			printf 'nothing saved in %s; %s left as it is\n' "$SAVED" "$VOMSDIR"
			exit 0
		fi
		install -d -m 0755 "$VOMSDIR"
		find "$VOMSDIR" -mindepth 1 -delete
		cp -a "$SAVED"/. "$VOMSDIR"/ || exit 1
		rm -rf "$SAVED"
		printf '%s restored\n' "$VOMSDIR"
	;;
	*)
		printf 'Usage: %s hide | restore\n' "$(basename "$0")" >&2
		exit 2
	;;
esac
