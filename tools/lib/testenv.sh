# shellcheck shell=bash
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
# The single entry point to the shared library.
#
# Scripts source this one file; it pulls in the other four. Nothing else in the
# repository may source them individually, so that the set stays consistent.
#
# TESTSUITE_HOME is derived from this file's own location rather than from the
# current directory, which is what lets a test be run from anywhere. Tests still
# need a writable checkout, because they write scratch files into their working
# directory - see run.sh.
# ------------------------------------------------------------------------------

if [ -n "${TESTENV_SOURCED:-}" ]; then
	return 0
fi
TESTENV_SOURCED=1

TESTENV_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TESTSUITE_HOME=$(cd -- "$TESTENV_DIR/../.." && pwd)
export TESTENV_DIR TESTSUITE_HOME

for lib in output checks credentials args report; do
	if [ ! -r "$TESTENV_DIR/$lib.sh" ]; then
		printf 'Shared library %s missing!\n' "$TESTENV_DIR/$lib.sh" >&2
		exit 2
	fi
	# shellcheck source=/dev/null
	source "$TESTENV_DIR/$lib.sh"
done

# Where setup.sh and run.sh leave their artifacts (reports, logs, the
# environment file describing what the testbed was configured with). Root
# creates it, the tester reads it.
: "${STATE_DIR:=/var/lib/glite-testsuites}"
export STATE_DIR

state_file()
{
	printf '%s/%s\n' "$STATE_DIR" "$1"
}

# For the drivers: a failure that is not a test result.
abort()
{
	printf '%s\n' "$*" >&2
	exit 1
}
