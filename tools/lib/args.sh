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
# The option block that every script in the repository has repeated verbatim.
#
# Individual test scripts keep their own argument loop - they are legacy code
# and the loop is only a handful of lines. This is for the drivers, which need
# the same options plus suite specific ones: parse_output_args consumes the
# common set and leaves the rest in $ARGS_LEFT for the caller to walk.
# ------------------------------------------------------------------------------

# Populated by parse_output_args and read by the caller. Exported because that
# is how a sourced library hands results to the script that sourced it.
WANT_HELP=0
OUTPUT_FILE=''
OUTPUT_TO_FILE=0
# The output option to hand down to the tests: -t, -c, -x, or empty to let
# them autodetect.
OUTPUT_OPT=''
ARGS_LEFT=()
export WANT_HELP OUTPUT_FILE OUTPUT_TO_FILE OUTPUT_OPT

# usage: parse_output_args "$@"
# Returns 3 on an unknown option or a missing -o argument.
parse_output_args()
{
	WANT_HELP=0
	OUTPUT_FILE=''
	OUTPUT_TO_FILE=0
	OUTPUT_OPT=''
	ARGS_LEFT=()

	while [ $# -gt 0 ]; do
		case "$1" in
			'-h' | '--help')
				WANT_HELP=1
				;;
			'-o' | '--output')
				shift
				if [ $# -lt 1 ]; then
					printf 'Option -o needs a file argument.\n' >&2
					return 3
				fi
				OUTPUT_FILE=$1
				OUTPUT_TO_FILE=1
				;;
			'-t' | '--text')
				setOutputASCII
				OUTPUT_OPT='-t'
				;;
			'-c' | '--color' | '--colour')
				setOutputColor
				OUTPUT_OPT='-c'
				;;
			'-x' | '--html')
				setOutputHTML
				OUTPUT_OPT='-x'
				;;
			*)
				ARGS_LEFT+=("$1")
				;;
		esac
		shift
	done

	return 0
}

# The options every script accepts, in the wording every --help has always
# used. Call it from showHelp after the script's own description.
output_usage()
{
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -o | --output 'file'   Redirect all output to the 'file' (stdout by default)."
	echo " -t | --text            Format output as plain ASCII text."
	echo " -c | --color           Format output as text with ANSI colours (autodetected by default)."
	echo " -x | --html            Format output as html."
}
