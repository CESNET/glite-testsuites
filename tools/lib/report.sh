# shellcheck shell=bash
# shellcheck disable=SC2154
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
# The minimal report the drivers write into $STATE_DIR.
#
# With -x the report is a self contained HTML page, otherwise plain text; every
# function here branches on $is_html, which setOutputHTML sets. That is also why
# the drivers never pass -o down to the tests: the report is assembled here from
# what the tests print.
#
# This replaced the EMI v3.2 test report template and the repository package
# lists, neither of which anyone fills in any more.
#
# SC2154: $lf, $is_html and the $SYS_* names come from output.sh and checks.sh,
# which testenv.sh sources before this file; shellcheck reads one file at a time
# and cannot know they are set by the time a report function is called.
# ------------------------------------------------------------------------------

# Emits HTML only in HTML mode.
report_html()
{
	if [ -n "${is_html:-}" ]; then
		printf '%s\n' "$*"
	fi
}

# report_header TITLE - opens the document.
report_header()
{
	local title="${1:-Test report}"

	report_html '<!DOCTYPE html>'
	report_html '<html lang="en">'
	report_html '<head>'
	report_html '<meta charset="utf-8">'
	report_html "<title>$(htmlcat_text "$title")</title>"
	report_html '<style>'
	report_html 'body { font-family: sans-serif; margin: 2em; }'
	report_html 'h1, h2, h3 { font-family: sans-serif; }'
	report_html 'pre { background: #f4f4f4; padding: 0.6em; overflow-x: auto; }'
	report_html 'table { border-collapse: collapse; }'
	report_html 'td, th { border: 1px solid #ccc; padding: 0.2em 0.6em; text-align: left; }'
	report_html '.failed { color: #b00020; font-weight: bold; }'
	report_html '.passed { color: #007a3c; font-weight: bold; }'
	report_html '</style>'
	report_html '</head>'
	report_html '<body>'
	report_html "<h1>$(htmlcat_text "$title")</h1>"

	if [ -z "${is_html:-}" ]; then
		printf '====================\n%s\n====================\n' "$title"
	fi
}

# report_section TITLE / report_subsection TITLE
report_section()
{
	if [ -n "${is_html:-}" ]; then
		printf '<h2>%s</h2>\n' "$(htmlcat_text "${1:-}")"
	else
		printf '\n---- %s ----\n' "${1:-}"
	fi
}

report_subsection()
{
	if [ -n "${is_html:-}" ]; then
		printf '<h3>%s</h3>\n' "$(htmlcat_text "${1:-}")"
	else
		printf '\n%s:\n' "${1:-}"
	fi
}

# Escapes a short piece of text given on the command line.
htmlcat_text()
{
	printf '%s' "${1:-}" | sed \
		-e 's/&/\&amp;/g' \
		-e 's/</\&lt;/g' \
		-e 's/>/\&gt;/g'
}

# report_paragraph TEXT
report_paragraph()
{
	if [ -n "${is_html:-}" ]; then
		printf '<p>%s</p>\n' "$(htmlcat_text "${1:-}")"
	else
		printf '%s\n' "${1:-}"
	fi
}

# report_pre FILE - include a file verbatim, escaped in HTML mode.
report_pre()
{
	local file=${1:-}

	if [ ! -r "$file" ]; then
		report_paragraph "(no output in $file)"
		return 0
	fi

	if [ -n "${is_html:-}" ]; then
		printf '<pre>'
		htmlcat "$file"
		printf '</pre>\n'
	else
		cat "$file"
	fi
}

# report_raw FILE - include a file that is already written in the format of the
# report itself. The tests' output is exactly that: under -x they emit HTML
# fragments (with <br> and their own <pre> blocks), under -t plain text. Escaping
# those would show the markup instead of rendering it, which is what the old
# reports did by pasting the fragments between the tests' own <PRE> markers.
report_raw()
{
	local file=${1:-}

	if [ ! -r "$file" ]; then
		report_paragraph "(no output in $file)"
		return 0
	fi

	cat "$file"
}

# report_script PATH - include the script that was run, as written. The setup
# script belongs in the report: it is the exact record of what was done to the
# testbed, and it is not otherwise recoverable afterwards.
report_script()
{
	local file=${1:-}

	if [ ! -r "$file" ]; then
		report_paragraph "(script $file not readable)"
		return 0
	fi

	report_subsection "Script: $file"
	report_pre "$file"
}

# report_fact LABEL VALUE - one row of the environment table.
report_fact()
{
	if [ -n "${is_html:-}" ]; then
		printf '<tr><td>%s</td><td>%s</td></tr>\n' "$(htmlcat_text "${1:-}")" "$(htmlcat_text "${2:-}")"
	else
		printf '%-16s %s\n' "${1:-}" "${2:-}"
	fi
}

# report_facts [SECONDS] - the testbed the run happened on. This is what
# gen_deployment_header used to emit, minus the EMI scenario wording and the
# distribution identifier guessed out of /etc/issue.
report_facts()
{
	local duration=${1:-}
	local os='unknown'
	local platform host

	if [ -r /etc/os-release ]; then
		# shellcheck source=/dev/null
		os=$(. /etc/os-release 2>/dev/null; printf '%s %s' "${PRETTY_NAME:-unknown}" "${VERSION:-}" | sed 's/ *$//')
	fi
	platform=$(uname -m 2> /dev/null)
	[ -n "$platform" ] || platform=$(uname -sr 2>/dev/null)
	host=$(hostname -f 2>/dev/null || hostname 2>/dev/null)

	if [ -n "${is_html:-}" ]; then
		printf '<table>\n'
	fi
	report_fact 'Host' "$host"
	report_fact 'Operating system' "$os"
	report_fact 'Platform' "$platform"
	report_fact 'Kernel' "$(uname -r 2>/dev/null)"
	report_fact 'Uptime' "$(uptime 2>/dev/null | sed 's/^\s*//')"
	if [ -n "$duration" ]; then
		report_fact 'Duration' "$((duration / 60)) min"
	fi
	report_fact 'User' "$(id -un) (uid $(id -u))"
	if [ -n "${is_html:-}" ]; then
		printf '</table>\n'
	fi
}

# report_verdict FAILED_COUNT TOTAL - the summary line the run exits on.
report_verdict()
{
	local failed=${1:-0}
	local total=${2:-}
	local cls='passed'
	local text='PASSED'

	if [ "${failed:-0}" -gt 0 ]; then
		cls='failed'
		text='FAILED'
	fi

	local plural='failures'
	if [ "$failed" -eq 1 ]; then
		plural='failure'
	fi

	if [ -n "$total" ]; then
		text="$text - $failed of $total checks failed"
	elif [ "$failed" -gt 0 ]; then
		text="$text - $failed $plural"
	fi

	if [ -n "${is_html:-}" ]; then
		printf '<p class="%s">%s</p>\n' "$cls" "$text"
	else
		printf '\n%s\n' "$text"
	fi
}

# --- Steps ------------------------------------------------------------
#
# The vocabulary the setup scripts report a sequence of actions with, as opposed
# to a test script's single check: report_step opens a line, report_note and
# report_dump add detail to it, report_fail_step closes it as a failure and
# counts it in $REPORT_FAILURES so that the script can end with a verdict.
#
# The names are prefixed because these files are sourced into every test script;
# 'step' and 'dump' alone would be asking for a collision.

REPORT_FAILURES=0

# Opens a report line, like the tests do - no newline, the status verb pads.
report_step()
{
	printf '%s' "$*"
}

# The reason goes below the line: the padding of the status verb would otherwise
# push it off the terminal column.
report_note()
{
	printf "   %s$lf" "$*"
}

# Output of a command that failed, indented in text mode and escaped in HTML.
report_dump()
{
	if [ ! -r "${1:-}" ]; then
		return 0
	fi
	if [ -n "${is_html:-}" ]; then
		printf '<pre>'
		htmlcat "$1"
		printf '</pre>\n'
	else
		$SYS_SED 's/^/   /' "$1"
	fi
}

report_fail_step()
{
	test_failed
	REPORT_FAILURES=$((REPORT_FAILURES + 1))
}

# report_tail - closes the document.
report_tail()
{
	report_html '<hr>'
	report_html "<p><small>Generated $(date -R 2>/dev/null || date) by ${TESTSUITE_HOME:-glite-testsuites}</small></p>"
	report_html '</body>'
	report_html '</html>'
}
