#!/usr/bin/env perl
# IMPLEMENTATION 2 of the DAC parse, for independent verification.
#
# pecos/dac_extract.py uses Python's csv module. This uses a regex state machine over each
# line. Comparing the two also settles whether any field contains an embedded record separator:
# a line-oriented parser and a record-oriented one agree on the row count only if none does.
# They agreed exactly (2,563,744 rows for the 05/2024 file).
#
# Prints "npi\torg_pac_id" for every cohort row carrying an organisation.
# Usage: perl pecos/verify/dac_parse.pl <npi_list_file> <DAC_national_file.csv>
use strict; use warnings;
my (%want, $rows);
open my $N, "<", $ARGV[0] or die "npi list: $!";
while (<$N>) { chomp; $want{$_} = 1 if length }
close $N;
open my $F, "<", $ARGV[1] or die "dac file: $!";
my $hdr = <$F>;
while (my $l = <$F>) {
    chomp $l; $rows++;
    my @f;
    while ($l =~ /\G(?:"((?:[^"]|"")*)"|([^,]*))(?:,|$)/gc) {
        my $v = defined $1 ? $1 : $2;
        $v =~ s/""/"/g if defined $1;
        push @f, $v;
        last if pos($l) >= length($l);
    }
    next if @f < 20;
    my ($npi, $org) = ($f[0], $f[19]);      # NPI is column 1, org_pac_id is column 20
    print "$npi\t$org\n" if exists $want{$npi} && length $org;
}
close $F;
print STDERR "perl parser: $rows data rows read\n";
