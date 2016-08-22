#!/usr/bin/perl
#vvvvvvvvvvvvvvvvvvvvvvvvv GUS4_STATUS vvvvvvvvvvvvvvvvvvvvvvvvv
  # GUS4_STATUS | SRes.OntologyTerm              | auto   | absent
  # GUS4_STATUS | SRes.SequenceOntology          | auto   | absent
  # GUS4_STATUS | Study.OntologyEntry            | auto   | absent
  # GUS4_STATUS | SRes.GOTerm                    | auto   | absent
  # GUS4_STATUS | Dots.RNAFeatureExon            | auto   | absent
  # GUS4_STATUS | RAD.SageTag                    | auto   | absent
  # GUS4_STATUS | RAD.Analysis                   | auto   | absent
  # GUS4_STATUS | ApiDB.Profile                  | auto   | absent
  # GUS4_STATUS | Study.Study                    | auto   | absent
  # GUS4_STATUS | Dots.Isolate                   | auto   | absent
  # GUS4_STATUS | DeprecatedTables               | auto   | absent
  # GUS4_STATUS | Pathway                        | auto   | absent
  # GUS4_STATUS | DoTS.SequenceVariation         | auto   | absent
  # GUS4_STATUS | RNASeq Junctions               | auto   | absent
  # GUS4_STATUS | Simple Rename                  | auto   | absent
  # GUS4_STATUS | ApiDB Tuning Gene              | auto   | absent
  # GUS4_STATUS | Rethink                        | auto   | absent
  # GUS4_STATUS | dots.gene                      | manual | unreviewed
die 'This file has broken or unreviewed GUS4_STATUS rules.  Please remove this line when all are fixed or absent';
#^^^^^^^^^^^^^^^^^^^^^^^^^ End GUS4_STATUS ^^^^^^^^^^^^^^^^^^^^

## make coverage files for broad strains similar to sanger files ...
# MAL1    .       .       111980  112182  .       .       .       Read "it188d04.p1k" ; Locations 1

use strict;


my $tot = {};
my @strains;
my %strains; ##records all the strains
my $totLen = 0;
my %pcr;
my %coverage;  ## @{$coverage{strain}->{seqid}}->[start,end]
foreach my $file (@ARGV){
  open(F, "$file");
  my @file = <F>;
  close F;
  my($seqid)= ($file =~ /\D(\d+)/);
  $seqid = "MAL".$seqid;
  my $def = shift @file;
  chomp $def;
  @strains = split(",",$def);
  $strains[0] =~ s/^.*\s(\S+)/$1/;
  foreach my $s (@strains){
    $strains{$s}++;
  }
  my %inCov;  ##record if in coverage region by strain
  my %starts;  ## starts ... first position by strain
  my $a = 0;
  for($a;$a<scalar(@file);$a++){
#    print STDERR "Processing $a\n" if $a % 10000 == 0;
    chomp $file[$a];
    my @t = split("",$file[$a]);
    for(my $b = 0;$b<scalar(@strains);$b++){
      ##here I need to get the loctions ...
      if($t[$b] > 0 && !$inCov{$strains[$b]}){  ##have character and am not in coverage therefore start
        $starts{$strains[$b]} = $a + 1;  ##indexed from 1
        $inCov{$strains[$b]} = 1;
      }elsif($t[$b] == 0 && $inCov{$strains[$b]}){  ##no character and incoverage so end of coverage
        push(@{$coverage{$strains[$b]}->{$seqid}},[$starts{$strains[$b]},$a]);
        $inCov{$strains[$b]} = 0; ##no longer in coverage
      }
    }
  }
  foreach my $s (keys%inCov){
    next unless $inCov{$s};
    push(@{$coverage{$s}->{$seqid}},[$starts{$s},$a+1]);
  }
}

foreach my $s (keys%strains){
  my $f = "$s.cov";
  $f = "106.cov" if $s =~ /^106/;
  open(F,">$f");
  foreach my $seq (keys %{$coverage{$s}}){
    foreach my $l (@{$coverage{$s}->{$seq}}){
      print F "$seq\t.\t.\t$l->[0]\t$l->[1]\t.\t.\t.\t.\n";
    }
  }
  close F;
}
