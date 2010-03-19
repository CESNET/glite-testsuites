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
$inst = $ENV{GLITE_PREFIX};
$inst = "/opt/glite" unless $inst;
$sbin = "$inst/sbin";
$bin = "$inst/bin";
$test = "$inst/examples";
$purge = "glite-lb-purge";
$status = "$test/glite-lb-job_status";
$log = "$test/glite-lb-job_log";
$prefix = "/tmp/purge_test_$$";
$delay = 60;

$ENV{PATH} .= ":$bin";
}

$option = shift;
$server = shift;

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

die "usage: $0 --i-want-to-purge server:port\n" unless $server;

sub logit {
	my $ids = shift;
	my $prefix = shift;
	my $failed = 0;

	for (qw/aborted cleared cancelled waiting/) {
		my $key = $_ eq waiting ? 'other' : $_;
		$id = `$test/glite-lb-$_.sh -m $server`;
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
	print_result ('bold green','done');
}
sub test_failed() {
	print_result ('bold red','-TEST FAILED-');
}


printf "** Hey, purging the whole database...";
system "$purge --server $server --return-list --aborted=0 --cleared=0 --cancelled=0 --other=0";
if ($!) {
	test_failed();
	die "$purge: $!\n";
}

test_done();

printf "** Logging test jobs\n";

if (!logit \%old,"${prefix}_old") {
	test_failed();
	die "!! failed\n";
}

print "** So far so good ";
test_done();

print "** sleeping $delay seconds...\n";
sleep $delay;
print "** OK, another set of jobs";
if (!logit \%new,"${prefix}_new") {
	test_failed();
	die "!! failed\n";
}

test_done();

$drain = $delay/10;
print "** draining other $drain seconds ...\n";
sleep $drain;

print "** test jobs:\n";

for (qw/aborted cleared cancelled other/) {
	print "$_:\n\t$old{$_}\n\t$new{$_}\n";
} 

print "** Dry run\n";
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

print "** Server defaults\n";

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

print "** Purge the first set of jobs\n";

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

print "** Purge the rest\n";
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


print "** Anything left?\n";
open LIST,"$purge --server $server --return-list --dry-run --aborted=0 --cleared=0 --cancelled=0 --other=0 | grep '^https://'|" or die "!! $purge\n";

$id = <LIST>;
close LIST;
die "!! Yes, but should not\n" if $id;
print "No, OK ";
test_done();

print "** Check zombies\n";
$failed = 0;

for (values(%old),values(%new)) {
		$stat = 'nic moc';
		$stat = `$status $_ | head -2 | tail -1`;
		chomp $stat;
		$stat =~ s/state :\s*//;

		print "$_ $stat ";
		if ($stat ne 'Purged') { $failed = 1; test_failed(); }
		else { test_done(); }
}

die "Jobs should be known and purged\n" if $failed;

print "\n** All tests passed **";
test_done();
exit 0;

END{ unlink glob "${prefix}*" if $prefix; }
