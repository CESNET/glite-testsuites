#!/usr/bin/perl 
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

use Term::ANSIColor;

BEGIN{
$inst = $ENV{GLITE_LB_LOCATION};
$inst = $ENV{GLITE_LOCATION} unless $inst;
$inst = "/opt/glite" unless $inst;
$sbin = "$inst/sbin";
$bin = "$inst/bin";
$test = "$inst/examples";
$t = "$inst/lib/glite-lb/examples"; if (-d $t) { $test = $t; }
$t = "$inst/lib64/glite-lb/examples"; if (-d $t) { $test = $t; }
$purge = "glite-lb-purge";
$status = "$test/glite-lb-job_status";
$log = "$test/glite-lb-job_log";
$prefix = "/tmp/purge_test_$$";
$delay = 60;
$html_output = 0;

$ENV{PATH} .= ":$bin";
}

$option = shift;
$server = shift;
$moreopts = shift;

if ($moreopts =~ m/-x/) { $html_output = 1; }

die qq{
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   This script will DESTROY ALL DATA in the specified bookkeeping server.

Don't run it unless you are absolutely sure what you are doing.
If you really mean it, the magic usage is:

   $0 --i-want-to-purge server:port

Good luck!

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	
} unless $option eq '--i-want-to-purge';

die "usage: $0 --i-want-to-purge server:port [-x]\n" unless $server;

sub logit {
	my $ids = shift;
	my $prefix = shift;
	my $failed = 0;

	for (qw/aborted cleared cancelled waiting/) {
		my $key = $_ eq waiting ? 'other' : $_;
		$id = `$test/glite-lb-$_.sh -m $server 2> /dev/null`;
		chomp $id;
		if ($?) {
			test_failed();
			die "$test/glite-lb-$_.sh"; }
		$id =~ s/EDG_JOBID=//;
		$ids->{$key} = $id;
#print "$status $id | head -1\n";
		$stat = `$status $id | head -2 | tail -1`;
		chomp $stat;
		$stat =~ s/state :\s*//;
#print "$id: ".uc($stat)." ".uc($_)."\n";
		$failed = 1 if uc($stat) ne uc($_);

		system "$log $id | grep -v '^[ 	]*\$' | grep -v '^Found' >${prefix}_$_";
	}

	!$failed;
}

sub print_result {
	my ($format,$text) = @_;
	print color $format;
#	($c)=qx(stty size)=~/\d+\s+(\d+)/;
#	printf "\015%${c}s\n","[ $text ]";
	printf "%s\n","[ $text ]";
	print color 'reset';
} 
sub test_done() {
	if ($html_output) { printf ("<font color=\"green\"><B>done</B></font><BR>\n"); }
	else { print_result ('bold green','done'); }
}
sub test_failed() {
	if ($html_output) { printf ("<font color=\"red\"><B>-TEST FAILED-</B></font><BR>\n"); }
	else { print_result ('bold red','-TEST FAILED-'); }
}
sub test_printf {
	if ($html_output) { printf("<BR><B>"); }
	printf "@_\n";
	if ($html_output) { printf("</B><BR>"); }
}


test_printf ("** Hey, purging the whole database...");
system "$purge --server $server --return-list --aborted=0 --cleared=0 --cancelled=0 --other=0";
if ($!) {
	test_failed();
	die "$purge: $!\n";
}

test_done();

test_printf ("** Logging test jobs\n");

if (!logit \%old,"${prefix}_old") {
	test_failed();
	die "!! failed\n";
}

test_printf ("** So far so good ");
test_done();

test_printf ("** sleeping $delay seconds...\n");
sleep $delay;
test_printf ("** OK, another set of jobs");
if (!logit \%new,"${prefix}_new") {
	test_failed();
	die "!! failed\n";
}

test_done();

$drain = $delay/10;
test_printf ("** draining other $drain seconds ...\n");
sleep $drain;

test_printf ("** test jobs:\n");

for (qw/aborted cleared cancelled other/) {
	print "$_:\n\t$old{$_}\n\t$new{$_}\n";
} 

test_printf ("** Dry run\n");
$failed = 0;

$half = $delay/2;
for (qw/aborted cleared cancelled other/) {
	open LIST,"$purge --server $server --dry-run --return-list --$_=${half}s| grep '^https://'|" or die "!! run $purge\n"; 

	$id = <LIST>; chomp $id;
	if ($old{$_} ne $id) {
		$failed = 1;
		print "!! $old{$_} (old $_) is not there";
		test_failed();
	}
	else {
		print "${half}s $_ $id ";
		test_done();
	}
	$id = <LIST>;
	if ($id) {
		$failed = 1;
		chomp $id;
		print "!! $id should not be there";
		test_failed();
	}
	close LIST;

	open LIST,"$purge --server $server --dry-run --return-list --$_=0s | grep '^https://'|" or die "!! run $purge\n"; 


	$cnt = 0;
	while ($id = <LIST>) {
		chomp $id;
		if ($old{$_} ne $id && $new{$_} ne $id) {
			$failed = 1;
			print "!! $id should not be there";
			test_failed();
		}
		else {
			print "0s $_ $id ";
			test_done();
		}
		$cnt++;
	}
	
	close LIST;
	if ($cnt != 2) {
		$failed = 1;
		print "!! bad number of $_ jobs ($cnt)";
		test_failed();
	}
}

if ($failed) {
	printf("aborting");
	test_failed();
	die "!! failed!"; }

test_printf ("** Server defaults\n");

open LIST,"$purge --server $server --dry-run --return-list | grep '^https://'|" or die "!! run $purge\n";

$failed = 0;
while ($id = <LIST>) {
	$failed = 1;
	printf "$id"; 
	test_failed(); }

if ($failed) {
	printf "!! Oops, should not do anything, too short defaults?";
	test_failed(); 
	die "!! failed!"; }

print "Nothing purged as expected ";
test_done();

test_printf ("** Purge the first set of jobs\n");

open DUMP,"$purge --server $server --server-dump --aborted=${half}s --cleared=${half}s --cancelled=${half}s --other=${half}s | grep '^Server dump:'|"
	or die "!! run $purge\n";

$dump = <DUMP>; chomp $dump; $dump =~ s/Server dump: //;
close DUMP;

unless ($dump) {
	printf "!! no dump file reported";
	test_failed();
	die "!! failed!"; }
#print "DEBUG: dump file: '$dump'\n";
@list = glob "${prefix}_old*";
system "cat @list | sort >${prefix}_old_all";
system "cat $dump | sed -e s/^.*DATE/DATE/ | sort >${prefix}_old_dump";
sleep 60;
system "diff ${prefix}_old_all ${prefix}_old_dump >/dev/null";

die "!! aggregate log and dump differ\n" if $? & 0xff00;

print "diff OK ";
test_done();

test_printf ("** Purge the rest\n");
open DUMP,"$purge --server $server --server-dump --aborted=0 --cleared=0 --cancelled=0 --other=0 | grep '^Server dump:'|"
	or die "!! run $purge\n";

$dump = <DUMP>; chomp $dump; $dump =~ s/Server dump: //;
close DUMP;

die "!! no dump file reported\n" unless $dump;
#print "DEBUG: dump file: '$dump'\n";
@list = glob "${prefix}_new*";
system "cat @list | sort >${prefix}_new_all";
system "cat $dump | sed -e s/^.*DATE/DATE/ | sort >${prefix}_new_dump";
system "diff ${prefix}_new_all ${prefix}_new_dump >/dev/null";

die "!! aggregate log and dump differ\n" if $? & 0xff00;

print "diff OK ";
test_done();


test_printf ("** Anything left?\n");
open LIST,"$purge --server $server --return-list --dry-run --aborted=0 --cleared=0 --cancelled=0 --other=0 | grep '^https://'|" or die "!! $purge\n";

$id = <LIST>;
close LIST;
die "!! Yes, but should not\n" if $id;
print "No, OK ";
test_done();

test_printf ("** Check zombies\n");
$failed = 0;

$errfile = $prefix . "_stat_err.tmp";
$statfile = $prefix . "_stat.tmp";

for (values(%old),values(%new)) {
		$jobid = $_;
		$stat = 'nic moc';
		system("$status $jobid > $statfile 2> $errfile");
		$stat = `cat $statfile | head -2 | tail -1`;
		chomp $stat;
		$stat =~ s/state :\s*//;
	
		$exitcode = system("grep \"Identifier removed\"	$errfile > /dev/null");
		if ( ! $exitcode ) { print "$jobid returned EIDRM"; }
		else { print "$jobid $stat "; }
		if ($stat ne 'Purged' && $exitcode ne 0) { $failed = 1; test_failed(); }
		else { test_done(); }
}

die "EIDRM or state Purged should have been returned for zombies\n" if $failed;

test_printf ("\n** All tests passed **");
test_done();
exit 0;

END{ unlink glob "${prefix}*" if $prefix; }
