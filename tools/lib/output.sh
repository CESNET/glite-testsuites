# shellcheck shell=bash
# shellcheck disable=SC2034,SC2059
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
# Output and status reporting for every test script in the repository.
#
# A test prints a description without a trailing newline, then closes the line
# with one of the status verbs, which pad it to the terminal width:
#
#     printf "Testing if the logger is listening"
#     check_listener $LB_LOGD $GLITE_LB_LOGGER_PORT && test_done || test_failed
#
# The output format is chosen by setOutputASCII, setOutputColor or
# setOutputHTML (the -t, -c and -x options). Tests must then print "${lf}"
# rather than a literal newline, because that is what turns into <br> in HTML;
# free-form text has to pass through htmlcat inside a <pre> block.
#
# Detail about why something failed accumulates in $testerrfile through
# set_error and update_error, and is flushed by print_error.
#
# SC2059 is disabled file-wide because the printf "${fmt}${lf}" form - a
# variable as the format string - is the API of this file, not a mistake.
# SC2034 is disabled because the begin_*/end_*/verb names below are the API
# consumed by the test scripts, not dead assignments.
# ------------------------------------------------------------------------------

# Do _not_ be fooled by non POSIX locale
LC_ALL=POSIX
export LC_ALL

TEST_ERROR=1
TEST_OK=0

# Where the error detail of the currently running check accumulates.
testerrfile=$$.err

# Seek for terminal size and, if needed, set default size. Every read here is
# ${VAR:-} guarded because a caller may have set -u before sourcing this file.
if [ -z "${LINES:-}" ] || [ -z "${COLUMNS:-}" ]; then
	if stty_size=$(stty size 2> /dev/null); then
		LINES=${stty_size%% *}
		COLUMNS=${stty_size##* }
	else
		LINES=24
		COLUMNS=80
		if [ "${TESTCOLS:-0}" -gt 0 ] 2> /dev/null; then
			COLUMNS=$TESTCOLS
		fi
	fi
fi
case "${LINES:-}" in (''|*[!0-9]*) LINES=24 ;; esac
case "${COLUMNS:-}" in (''|*[!0-9]*) COLUMNS=80 ;; esac
export LINES COLUMNS

set_test()
{
	test_done="${spacefill}${begin_green}done${end_green}"
	test_running="${spacefill}${begin_green}running${end_green}"
	test_failed="${spacefill}${begin_red}-TEST FAILED-${end_red}"
	test_missed="${spacefill}${begin_red}missing${end_red}"
	test_skipped="${spacefill}${begin_yellow}skipped${end_yellow}"
	test_warning="${spacefill}${begin_yellow}warning${end_yellow}"

	test_start="${spacefill}${begin_green}start${end_green}"
	test_end="${spacefill}${begin_green}end${end_green}"
}

# What every status verb also does: leave its name, one per line, in the file the
# caller of the test named in $TEST_VERDICTS. A driver running a whole suite needs to
# know whether a test that came back nonzero reported anything at all before it
# stopped, and the verbs as printed are no use for that - 'done', the same word under
# ANSI colours and again under <font> tags. Nothing is said when no file was named,
# which is how a test run by hand behaves: it reports on the terminal and nowhere
# else. The word goes down before the line is printed, because a test whose output is
# a pipe somebody closed dies of SIGPIPE on the printf and would then report nothing.
verdict_note()
{
	if [ -n "${TEST_VERDICTS:-}" ]; then
		printf '%s\n' "$1" >> "$TEST_VERDICTS" 2> /dev/null
	fi
	return 0
}

test_done()	{ verdict_note 'done';	printf "${test_done}${lf}"; }
test_running()	{ verdict_note 'running';	printf "${test_running}${lf}"; }
test_failed()	{ verdict_note 'failed';	printf "${test_failed}${lf}"; }
test_missed()	{ verdict_note 'missed';	printf "${test_missed}${lf}"; }
test_skipped()	{ verdict_note 'skipped';	printf "${test_skipped}${lf}"; }
test_warning()	{ verdict_note 'warning';	printf "${test_warning}${lf}"; }

test_start()	{ syslog "${test_start}"; reset_error; }
test_end()	{ syslog "${test_end}"; reset_error; }

# set output to ASCII (without colors)
setOutputASCII()
{
	lf="\n"
	spacefill="..."

	begin_bold=""
	begin_black=""
	begin_red=""
	begin_green=""
	begin_yellow=""
	begin_blue=""
	begin_magenta=""
	begin_cyan=""
	begin_white=""

	end_bold=""
	end_black=""
	end_red=""
	end_green=""
	end_yellow=""
	end_blue=""
	end_magenta=""
	end_cyan=""
	end_white=""

	unset is_html
	set_test
}

# set output to ASCII with ANSI colors
setOutputColor()
{
	local esc normal
	esc=$(echo -en "\033")
	normal="${esc}[0m" # unsets color to term's fg color
	lf="\n"
	spacefill=$(echo -en "\015${esc}[${COLUMNS}C${esc}[15D")

	begin_bold="${esc}[0;1m"
	begin_black="${esc}[0;30m"
	begin_red="${esc}[0;31m"
	begin_green="${esc}[0;32m"
	begin_yellow="${esc}[0;33m"
	begin_blue="${esc}[0;34m"
	begin_magenta="${esc}[0;35m"
	begin_cyan="${esc}[0;36m"
	begin_white="${esc}[0;37m"

	end_bold="$normal"
	end_black="$normal"
	end_red="$normal"
	end_green="$normal"
	end_yellow="$normal"
	end_blue="$normal"
	end_magenta="$normal"
	end_cyan="$normal"
	end_white="$normal"

	unset is_html
	set_test
}

# set output to HTML
setOutputHTML()
{
	local ENDFONT="</font>"
	lf="<br>\n"
	spacefill="&nbsp;&nbsp;&nbsp;"
	is_html=1

	begin_bold="<b>"
	begin_black="<b><font color=\"black\">"
	begin_red="<b><font color=\"red\">"
	begin_green="<b><font color=\"green\">"
	begin_yellow="<b><font color=\"orange\">"
	begin_blue="<b><font color=\"blue\">"
	begin_magenta="<b><font color=\"magenta\">"
	begin_cyan="<b><font color=\"cyan\">"
	begin_white="<b><font color=\"white\">"

	end_bold="</b>"
	end_black="$ENDFONT</b>"
	end_red="$ENDFONT</b>"
	end_yellow="$ENDFONT</b>"
	end_blue="$ENDFONT</b>"
	end_magenta="$ENDFONT</b>"
	end_cyan="$ENDFONT</b>"
	end_white="$ENDFONT</b>"

	set_test
}

reset_error()
{
	rm -f "$testerrfile"
}

set_error()
{
	printf '%s '"${lf}"'\n' "$*" > "$testerrfile"
}

update_error()
{
	printf '%s; ' "$*" >> "$testerrfile"
}

print_error()
{
	printf "\t${begin_red}Error${end_red}: %s ${lf}" "$*"

	if [ -f "$testerrfile" ]; then
		printf "\t${begin_red}Error${end_red}: %s ${lf}" "$(cat "$testerrfile")"
	fi
	reset_error
}

print_warning()
{
	printf "${begin_magenta}Warning${end_magenta}: %s ${lf}" "$*"
}

print_info()
{
	printf "${begin_blue}Info${end_blue}: %s ${lf}" "$*"
}

print_newline()
{
	printf "${lf}"
}

syslog()
{
	local tmp
	tmp=$(date +'%b %d %H:%M:%S')
	printf "${begin_bold}${tmp} $(hostname) ${progname:-}${end_bold}: %s ${lf}" "$*"
}

# Escape text so that it can be embedded in an HTML <pre> block.
htmlcat()
{
	sed \
		-e 's/&/\&amp;/g' \
		-e 's/</\&lt;/g' \
		-e 's/>/\&gt;/g' \
		"$1"
}

# by default set output to color if possible
if test -t 1 -a "${TERM:-}" != "raw" -a "${TERM:-}" != "dumb" && stty size <& 1 > /dev/null 2>&1; then
	setOutputColor
else
	setOutputASCII
fi
