#! /usr/bin/perl -w

use strict;
my ($no, $out);

while (<>) {
	if (/^Message #([0-9]+) Received:\s*(.*)/) {
		if ($out and $no) {
			open FH, '>', "cms-$no.json" or die "$!";
			printf FH "%s", "$out";
			close FH;
		}
		$no = $1;
		$out = $2;
	} else {
		$out .= $_;
	}
}
