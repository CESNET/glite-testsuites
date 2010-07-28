# $Header$
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
# ------------------------------------------------------------------------------
# Definition of test script return messages
#
#   The test scripts should use the variables test_done and test_failed to
#   report whether they failed or succeeded. 
#
#   The variable test_reset is used to turn off all attributes and switch 
#   to the standard character set.
#
#    \033          ascii ESCape
#    \033[<NUM>G   move to column <NUM> (linux console, xterm, not vt100)
#    \033[<NUM>C   move <NUM> columns forward but only upto last column
#    \033[<NUM>D   move <NUM> columns backward but only upto first column
#    \033[<NUM>A   move <NUM> rows up
#    \033[<NUM>B   move <NUM> rows down
#    \033[1m       switch on bold
#    \033[31m      switch on red
#    \033[32m      switch on green
#    \033[33m      switch on yellow
#    \033[m        switch off color/bold
#    \017          exit alternate mode (xterm, vt100, linux console)
#    \033[10m      exit alternate mode (linux console)
#    \015          carriage return (without newline)
#
#   See also United Linux or OpenSUSE /etc/rc.status script
#
# ------------------------------------------------------------------------------

# Do _not_ be fooled by non POSIX locale
LC_ALL=POSIX
export LC_ALL

# Seek for terminal size and, if needed, set default size
if [ -z "${LINES}" -o -z "${COLUMNS}" ]; then
	stty_size=`stty size 2> /dev/null`
	if [ $? = 0 ]; then  
		LINES=`echo ${stty_size} | awk '{print $1}'`
		COLUMNS=`echo ${stty_size} | awk '{print $2}'`
	else
		LINES=24
		if [ -z $LBTSTCOLS ]; then
			COLUMNS=$LBTSTCOLS
		else		
			COLUMNS=80
		fi
	fi
fi
if [ ! $LINES -ge 0 ]; then LINES=24; fi
if [ ! $COLUMNS -ge 0 ]; then COLUMNS=80; fi
export LINES COLUMNS

# default return values
TEST_ERROR=1
TEST_OK=0

# test error file
testerrfile=$$.err

function set_test()
{
test_done="${spacefill}${begin_green}done${end_green}"
test_running="${spacefill}${begin_green}running${end_green}"
test_failed="${spacefill}${begin_red}-TEST FAILED-${end_red}"
test_missed="${spacefill}${begin_red}missing${end_red}"
test_skipped="${spacefill}${begin_yellow}skipped${end_yellow}"
test_dead="${spacefill}${begin_red}dead${end_red}"
test_unused="${spacefill}${begin_bold}unused${end_bold}"
test_unknown="${spacefill}${begin_yellow}unknown${end_yellow}"

test_start="${spacefill}${begin_green}start${end_green}"
test_end="${spacefill}${begin_green}end${end_green}"
}

function test_done()	{ printf "${test_done}${lf}"; }
function test_running()	{ printf "${test_running}${lf}"; }
function test_failed()	{ printf "${test_failed}${lf}"; }
function test_missed()	{ printf "${test_missed}${lf}"; }
function test_skipped()	{ printf "${test_skipped}${lf}"; }
function test_dead()	{ printf "${test_dead}${lf}"; }
function test_unused()	{ printf "${test_unused}${lf}"; }
function test_unknown	{ printf "${test_unknown}${lf}"; }
function test_start()	{ 
	syslog "${test_start}"; 
	reset_error 
}
function test_end()	{ 
	syslog "${test_end}"; 
	reset_error 
}

# set output to ASCII (without colors)
function setOutputASCII()
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

set_test
}

# set output to ASCII with ANSI colors
function setOutputColor()
{
local esc=`echo -en "\033"`
local normal="${esc}[0m" # unsets color to term's fg color
lf="\n"
spacefill=`echo -en "\015${esc}[${COLUMNS}C${esc}[15D"`

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

set_test
}

# set output to HTML
function setOutputHTML()
{
local ENDFONT="</font>"
lf="<br />\n"
spacefill="&nbsp;&nbsp;&nbsp;"
is_html=1

begin_bold="<b>"
begin_black="<font color=\"black\">"
begin_red="<font color=\"red\">"
begin_green="<font color=\"green\">"
begin_yellow="<font color=\"yellow\">"
begin_blue="<font color=\"blue\">"
begin_magenta="<font color=\"magenta\">"
begin_cyan="<font color=\"cyan\">"
begin_white="<font color=\"white\">"

end_bold="</b>"
end_black="$ENDFONT"
end_red="$ENDFONT"
end_green="$ENDFONT"
end_yellow="$ENDFONT"
end_blue="$ENDFONT"
end_magenta="$ENDFONT"
end_cyan="$ENDFONT"
end_white="$ENDFONT"

set_test
}

function reset_error()
{
	rm -f $testerrfile
}

function set_error()
{
	printf "%s ${lf}" "$*" > $testerrfile
}

function update_error()
{
	printf "%s; " "$*" >> $testerrfile
}

function print_error()
{
	printf "${begin_red}Error${end_red}: %s ${lf}" "$*"

	if [ -f $testerrfile ]; then
		printf "${begin_red}Error${end_red}: %s ${lf}" "`cat $testerrfile`"
	fi
	reset_error
}

function print_warning()
{
	printf "${begin_magenta}Warning${end_magenta}: %s ${lf}" "$*"
}

function print_info()
{
	printf "${begin_blue}Info${end_blue}: %s ${lf}" "$*"
}

function print_newline()
{
	printf "${lf}"
}

function syslog() 
{
        local tmp="`date +'%b %d %H:%M:%S'` `hostname` $progname"
	printf "${begin_bold}${tmp}${end_bold}: %s ${lf}" "$*"
}

function dprintf()
{
	if [ $DEBUG -gt 0 ]; then 
		printf "%s${lf}" "$*"
	fi
}

# by default set output to color if possible
if test -t 1 -a "$TERM" != "raw" -a "$TERM" != "dumb" && stty size <&1 > /dev/null 2>&1 ; then
	setOutputColor
else
	setOutputASCII
fi

