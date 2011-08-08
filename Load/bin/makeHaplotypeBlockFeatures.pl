#!/usr/bin/perl

use strict;
use IO::File;
use Getopt::Long;

my ($help, $mapFile, $microstatGff, $outputGff,$seqLengthFile);

&GetOptions('help|h' => \$help,
            'mapFile=s' => \$mapFile,
            'microstatGff=s' => \$microstatGff,
            'seqLengthFile=s' => \$seqLengthFile,
            'outputGff=s' => \$outputGff,
           );
 
unless(-e $microstatGff && $mapFile && $outputGff) {
  print STDERR "usage:  perl makeHaplotypeBlockFeatures.pl  --mapFile  <Microsatellites-Centimorgan mapping file> --microstatGff  <a GFF file containing the microsatellite features used for constructing the physical map>   --seqLengthFile  <A file listing the chromosomes and their length>   --outputGff  <Output file to print the GFF features to>\n";
  exit;
}




my (%IdChrMap, %cMorgan);

open (mapFile,$mapFile);
while (<mapFile>) {   

   my @elements = split(/\t/,$_);
   chomp(@elements);

   next unless ($elements[1] =~ /G/ || $elements[3] ne ".");

   $cMorgan{$elements[1]} = $elements[3];
   
   if ($elements[4] < 10) {
       $IdChrMap{$elements[1]} = "Pf3D7_0".$elements[4];
      } else {
       $IdChrMap{$elements[1]} = "Pf3D7_".$elements[4];
      }
}
close(mapFile);




my (%chrLength);

open(lengthFile,$seqLengthFile);
while (<lengthFile>) {

  my @list = split(/\t/,$_);
  chomp(@list);
  $list[1] =~ s/,//g;

  $chrLength{$list[0]} = $list[1];
}
close(lengthFile);


my (%fwdCood,%revCood,%strand);

open (gffFile, $microstatGff);
while (<gffFile>){
  chomp;
  my $gffLine = $_;
  my @elements = split(/\t/,$gffLine);
  my $chromID = $elements[0];

  my @geoID = split(/ /, $elements[8]);
  $geoID[1] =~ s/;//g;

  next unless (exists $IdChrMap{$geoID[1]});

  $fwdCood{$chromID}{$geoID[1]} = $elements[3];
  $revCood{$chromID}{$geoID[1]} = $elements[4];
  $strand{$chromID}{$geoID[1]} = $elements[6];
}
close(gffFile);




my (%conservativeStart, %conservativeEnd, %liberalStart, %liberalEnd, %haplotypeCMorgan);
my ($consrvStart,$consrvEnd,$featureCount,$prevChrVal,$prevCMorgan);

$featureCount = 0;

foreach my $chromosome (sort keys %fwdCood){

  foreach my $stsId (sort {$fwdCood{$chromosome}{$a} <=> $fwdCood{$chromosome}{$b} } (keys %{ $fwdCood{$chromosome} })) {

     if ($prevCMorgan ne $cMorgan{$stsId}) {
        $haplotypeCMorgan{$chromosome}{$featureCount} = $cMorgan{$stsId};
        $conservativeStart{$chromosome}{$featureCount} = $fwdCood{$chromosome}{$stsId};
        $liberalStart{$chromosome}{$featureCount} = $consrvEnd+1;
        
        if ($featureCount > 0) {
          $conservativeEnd{$prevChrVal}{$featureCount-1} = $consrvEnd;
          $liberalEnd{$prevChrVal}{$featureCount-1} = $fwdCood{$chromosome}{$stsId} - 1;
        }
       $featureCount++;
     }
     
     $consrvStart = $fwdCood{$chromosome}{$stsId};
     $prevCMorgan = $cMorgan{$stsId};
     $prevChrVal = $chromosome;
     $consrvEnd = $revCood{$chromosome}{$stsId};
  }
  $liberalEnd{$prevChrVal}{$featureCount-1} = $chrLength{$prevChrVal};
  $conservativeEnd{$prevChrVal}{$featureCount-1} = $consrvEnd; 
  $featureCount = 0;
  $consrvEnd = 0;
}


open (outGff, ">$outputGff");

foreach my $chromosome (sort keys %conservativeStart){
  foreach my $centiMorgan (sort {$conservativeStart{$chromosome}{$a} <=> $conservativeStart{$chromosome}{$b} } (keys %{ $conservativeStart{$chromosome} })) {
    my $chr = $chromosome;
    $chr =~ s/psu\|//g;
    print (outGff "$chr\tFerdigLab\thaplotype_block\t$conservativeStart{$chromosome}{$centiMorgan}\t$conservativeEnd{$chromosome}{$centiMorgan}\t.\t.\t.\tStart_Min $liberalStart{$chromosome}{$centiMorgan}; End_Max $liberalEnd{$chromosome}{$centiMorgan}; CentiMorgan $haplotypeCMorgan{$chromosome}{$centiMorgan}; Name HpB_".$chr."_".($centiMorgan+1)."\n");
  }
}
