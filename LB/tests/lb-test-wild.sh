#! /bin/bash
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

# read common definitions and functions
COMMON=lb-common.sh
if [ ! -r ${COMMON} ]; then
	echo -en "Common definitions '${COMMON}' missing!\n"
	exit 2
fi
source ${COMMON}

# show help and usage
progname=`basename $0`
showHelp()
{
cat << EndHelpHeader

Launch test in the wild real world against WMS.

Tests (everything with normal jobs and collections):
 - submit
 - cancel
 - output
 - check proper end states (done, aborted, cancelled, cleared)
 - all appropriate components send events

Prerequisities:
 - LB server

Returned values:
    Exit $TEST_OK: Test Passed
    Exit $TEST_ERROR: Test Failed
    Exit 2: Wrong Input

EndHelpHeader

	echo "Usage: $progname [OPTIONS] HOST"
	echo "Options:"
	echo " -h | --help            Show this help message."
	echo " -n | --number          Number of batches (default: 2)."
	echo " -v | --vo              Virtual organization (default: \`voms-proxy-info --vo\`)"
	echo " -w | --world           World test (by default limited on CESNET node)"
	echo " -t | --test            Type of test (default: all). Possible tests:"
	echo "                        done fail cancel done_coll fail_coll cancel_coll all"
	echo " -f | --format          output format (default: color), color/html/text"
	echo ""
	echo "where HOST is the LB server host, it must be specified everytime."
	echo ""
	echo "Example for low intrusive test (one job only per test and sequentially):"
	echo "  for t in done fail cancel done_coll fail_coll cancel_coll; do"
	echo "    ./lb-test-wild.sh -n 1 -w -f html --test \$t"
	echo "  done"
}


function fatal() {
	ret=$1
	shift
	print_error " $@"
	exit $ret
}


if [ -z "$1" ]; then
	showHelp
	exit 2
fi
while test -n "$1"
do
	case "$1" in
		"-h" | "--help") showHelp && exit 2 ;;
		"-n" | "--number") shift && N=$1 ;;
		"-v" | "--vo") shift && VO="$1" ;;
		"-w" | "--world") NOREQ='#' ;;
		"-t" | "--test")
			shift
			TEST="$1"
			if test x"$TEST" = x"all"; then unset TEST; fi
			;;
		"-f" | "--format")
			shift
			case "$1" in
				"text") setOutputASCII ;;
				"color") setOutputColor ;;
				"html") setOutputHTML ;;
			esac
			;;
		-*) ;;
		*) LB_HOST=$1 ;;
	esac
	shift
done


N=${N:-2}
voms-proxy-info >/dev/null || fatal 2 "No VOMS proxy certificate!"
if test -z "$VO"; then
	VO=`voms-proxy-info --vo`
fi
if test -z "$VO"; then
	fatal 2 "No VO!"
fi

#
# For available CEs, check:
#
#   lcg-infosites --vo voce ce
#
JDL_HEADER="LBAddress = \"$LB_HOST\";
VirtualOrganisation = \"$VO\";
#${NOREQ}Requirements = other.GlueCEInfoHostname==\"ce2.egee.cesnet.cz\";
${NOREQ}Requirements = other.GlueCEInfoHostname==\"cream1.egee.cesnet.cz\" || other.GlueCEInfoHostname==\"cream2.grid.cesnet.cz\";

RetryCount=2;"


# $1 - description
# $2 - file prefix
function submit() {
	echo -n "[wild] submit ($1 test): "
	glite-wms-job-submit -a $2.jdl >"submit-$2.log" || fatal $TEST_ERROR "Can't submit job ($1 test)"
	date '+%Y-%m-%d %H:%M:%S' >> log
	cat "submit-$2.log" >> log
	jobid=`cat "submit-$2.log" | $SYS_GREP ^https:`
	echo -en "$jobid${lf}"
	echo "$jobid	$2"  >> wild-joblist.txt
	rm -f "submit-$2.log"

	i=${#jobs[*]}
	jobs[$i]=$jobid
	job_cats[$i]="$2";
}


# $2 - jobid
function cancel() {
	echo -en "[wild] cancel $1${lf}"
	echo "y" | glite-wms-job-cancel $1 >>log || fatal $TEST_ERROR "Can't cancel job $1"
}


function submit_fail() {
cat > fail.jdl <<EOF
[

Type = "job";

$JDL_HEADER

StdOutput = "std.out";
StdError = "std.err";
OutputSandbox = { "std.out", "std.err" };

Executable = "/bin/something-that-does-not-exist";
Arguments = "Ahoj, svete!";

];
EOF
	submit "fail" fail
}


function submit_done() {
cat > launch.sh <<EOF
#! /bin/sh
hostname -f
echo "\$@"
EOF
chmod +x launch.sh

cat > done.jdl <<EOF
[

Type = "job";

$JDL_HEADER

Executable = "launch.sh";
Arguments = "Ahoj, svete!";
InputSandbox = "launch.sh";
StdOutput = "std.out";
StdError = "std.err";
OutputSandbox = { "std.out", "std.err" };

];
EOF
	submit "done" done
}


function submit_collection_fail() {
cat > launch.sh <<EOF
#! /bin/sh
hostname -f
echo "$@"
EOF
chmod +x launch.sh

cat > fail_coll.jdl <<EOF
[

Type = "Collection";

$JDL_HEADER

InputSandbox = "launch.sh";

Nodes = {
	[
		Executable = "launch.sh";
		Arguments = "Ahoj, svete!";
		StdOutput = "std1.out";
		StdError = "std1.err";
		OutputSandbox = { "std1.out", "std1.err" };
	],
	[
		Executable = "/bin/something-that-does-not-exist-$$";
		Arguments = "Ahoj, svete!";
		StdOutput = "std2.out";
		StdError = "std2.err";
		OutputSandbox = { "std2.out", "std2.err" };
	]
}

]
EOF
	submit "collection to fail" fail_coll
}


function submit_collection_done() {
cat > launch.sh <<EOF
#! /bin/sh
hostname -f
echo "$@"
EOF
chmod +x launch.sh

cat > done_coll.jdl <<EOF
[

Type = "Collection";

$JDL_HEADER

InputSandbox = "launch.sh";

Nodes = {
	[
		Executable = "launch.sh";
		Arguments = "Ahoj, svete!";
		StdOutput = "std1.out";
		StdError = "std1.err";
		OutputSandbox = { "std1.out", "std1.err" };
	],
	[
		Executable = "launch.sh";
		Arguments = "Ahoj, svete!";
	]
};

];
EOF
	submit "collection to done" done_coll
}


function check_status() {
	prev_status=${stats[$1]}
	jobid=${jobs[$1]}
	glite-wms-job-status -v 0 $jobid >$$.stat.log || fatal 2 "Can't get job status"
	status=`cat $$.stat.log | $SYS_GREP '^Current Status: ' | $SYS_SED -e 's/^Current Status: [ \t]*\([a-zA-Z]*\).*/\1/'`
	if [ x"$status" != x"$prev_status" ]; then
		date '+%Y-%m-%d %H:%M:%S' >> log
		cat $$.stat.log >> log

		if [ x"${job_cats[$1]}" != x"" ]; then
			desc=" (${job_cats[$1]} test)";
		else
			desc=""
		fi
		date '+[wild] %Y-%m-%d %H:%M:%S ' | tr -d '\n'
		echo -en "$jobid $status$desc${lf}"
		stats[$1]="$status"
	fi
	rm -f $$.stat.log
}


# -- init --

rm -f log
touch $$.err
[ ! -z "${LB_HOST}" ] || fatal 2 "No L&B server specified!"

check_binaries $SYS_GREP $SYS_SED || fatal 2 "not all needed system binaries available"

fail=$TEST_OK

# -- launch the beast --

{
test_start

for ((pass=0;pass<N;pass++)); do
	test -z "$TEST" -o x"$TEST" = x"done" && submit_done
	test -z "$TEST" -o x"$TEST" = x"fail" && submit_fail
	test -z "$TEST" -o x"$TEST" = x"fail_coll" && submit_collection_fail
	test -z "$TEST" -o x"$TEST" = x"done_coll" && submit_collection_done
	test -z "$TEST" -o x"$TEST" = x"cancel" && submit_done && job_cats[$i]='cancel'
	test -z "$TEST" -o x"$TEST" = x"cancel_coll" && submit_collection_done && job_cats[$i]='cancel_coll'
done

echo -en "[wild] sleep before cancel...${lf}"
sleep 10
for ((i=0; i<${#job_cats[*]}; i++)); do
	if test x"${job_cats[$i]}" = x"cancel" -o x"${job_cats[$i]}" = x"cancel_coll" ; then
		cancel ${jobs[$i]}
	fi
done
printf "[wild] submitted" && test_done
echo -en "[wild] ================================${lf}"


# -- wait for terminal states --

n=${#jobs[*]}
quit=0
while test $quit -eq 0; do
	quit=1
	for ((i=0;i<n;i++)); do
		check_status $i
		if test x"$status" != x'Aborted' -a x"$status" != x'Done' -a x"$status" != x'Cleared' -a x"$status" != x"Cancelled" -a x"$status" != x"Purged"; then
			quit=0
		fi
	done
	sleep 30
done
printf "[wild] all jobs finished" && test_done
echo -en "[wild] ================================${lf}"


# -- log full states --

for ((i=0;i<n;i++)); do
	glite-wms-job-status -v 3 ${jobs[$i]} >> log
done


# -- check states --
for ((i=0;i<n;i++)); do
	jobid="${jobs[$i]}"
	status="${stats[$i]}"

	glite-lb-job_log "$jobid" > $$.ulm.log || fatal $TEST_ERROR "Can't query events for '$jobid'"
	components=`cat $$.ulm.log | head -n -1 | $SYS_GREP -v '^$' | $SYS_SED -e 's/.*DG\.SOURCE="\([^"]*\)".*/\1/' | sort -f | uniq | tr '\n' ' ' | $SYS_SED 's/ $//'`
	rm -f $$.ulm.log

	expected_status=''
	expected_components=''
	nocategory=''
	case "${job_cats[$i]}" in
	done)
		expected_status='Done'
		expected_components='JobController LogMonitor LRMS NetworkServer WorkloadManager'
		;;
	done_coll)
		expected_status='Done'
		expected_components='LBServer NetworkServer WorkloadManager'
		;;
	fail)
		expected_status='Aborted'
		expected_components='JobController LogMonitor LRMS NetworkServer WorkloadManager'
		;;
	fail_coll)
		expected_status='Aborted'
		expected_components='LBServer NetworkServer WorkloadManager'
		;;
	cancel)
		expected_status='Cancelled'
		expected_components='JobController LogMonitor NetworkServer WorkloadManager'
		;;
	cancel_coll)
		expected_status='Cancelled'
		expected_components='NetworkServer WorkloadManager'
		;;
	*)
		nocategory="no category"
		;;
	esac

	if test x"$nocategory" != x""; then
		printf "[wild] $jobid: '$status' OK (no category)" && test_done
	else
		if test x"$expected_status" = x"$status"; then
			printf "[wild] $jobid: '$status' OK (${job_cats[$i]})" && test_done
		else
			if test x"${job_cats[$i]}" = x"cancel_coll" -a x"$status" = x"Cleared"; then
				printf "[wild] $jobid: expected '$expected_status', got '$status' (${job_cats[$i]}), so be it!" && test_done
			else
				print_error "$jobid: expected '$expected_status', got '$status'!" && test_failed
				fail=$TEST_ERROR
			fi
		fi

		if test x"$expected_components" = x"$components"; then
			printf "[wild]     components: $components OK" && test_done
		else
			case "${job_cats[$i]}" in
			cancel|cancel_coll)
				echo -en "[wild]     components: $components ?${lf}"
				;;
			*)
				print_error "    components: $components DIFFERS " && test_failed
				fail=$TEST_ERROR
				;;
			esac
		fi
	fi
done
echo -en "[wild] ================================${lf}"


# -- only for done jobs: fetch output --

echo -en "[wild] job output test${lf}"
mkdir -p "jobOutput.$$" 2>/dev/null
for ((i=0; i<${#job_cats[*]}; i++)); do
	jobid="${jobs[$i]}"
	case "${job_cats[$i]}" in
	done)
		echo -en "[wild] fetching output from $jobid${lf}"
		echo "y" | glite-wms-job-output --dir "jobOutput.$$/$i" "$jobid" >> log
		if test "$?" = "0"; then
			printf "[wild] output of '$jobid' fetched" && test_done
		else
			print_error "can't fetch output from $jobid!" && test_failed
			fail=$TEST_ERROR
		fi
		;;
	done_coll)
		echo -en "[wild] fetching output from $jobid${lf}"
		glite-wms-job-status -v 0 "$jobid" | $SYS_GREP '^ .*https:' | $SYS_SED 's/.*https:/https:/' > $$.subjobs.log
		if test x"`wc -l $$.subjobs.log | $SYS_SED 's/\s*\([0-9]*\).*/\1/'`" != x"2"; then
			print_error "error, some offspring of $jobid were spawned or eaten!" && test_failed
			fail=$TEST_ERROR
		fi
		j=1
		for subjobid in `cat $$.subjobs.log`; do
			echo "y" | glite-wms-job-output --dir "jobOutput.$$/$i-$j" "$subjobid" >> log
			if test "$?" = "0"; then
				printf "[wild] output of $subjobid ($j. offspring of $jobid) fetched" && test_done
			else
				print_error "can't fetch output from $subjobid!" && test_failed
				fail=$TEST_ERROR
			fi
			j=$((j+1))
		done
		rm -f $$.subjobs.log
		;;
	esac
done


# -- result data --
echo -n "[wild] outputs: "
find "jobOutput.$$" -type f
echo -en "${lf}"


# -- only for done jobs: wait for cleared --

n=${#jobs[*]}
quit=0
cleared_fail=0
echo -en "[wild] waiting for cleared states...${lf}"
while test $quit -eq 0; do
	quit=1
	for ((i=0;i<n;i++)); do
		if test x"${job_cats[$i]}" = x"done" -o x"${job_cats[$i]}" = x"done_coll"; then
			check_status $i
			case "$status" in
			'Cleared')
				;;
			'Cancelled'|'Aborted'|'Purged')
				cleared_fail=1
				;;
			*)
				quit=0
				;;
			esac
		fi
	done
	sleep 10
done
if test x"$cleared_fail" = x"0"; then
	printf "[wild] all jobs in done cleared" && test_done
else
	print_error "not all expected jobs in cleared state!" && test_failed
	fail=$TEST_ERROR
fi

test_end
}

exit $fail
