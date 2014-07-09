package ApiCommonData::Load::MapAndPrintEpitopes;
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

use lib "$ENV{GUS_HOME}/lib/perl";
use Getopt::Long;
use Switch;
use strict;

sub mapEpitopes{
  my ($subjSeq, $subId, $seqId, $epitopes, $outFile, $debug) = @_;

      print STDERR "Getting epitopes...\n" if $debug;

      my $foundAll = 1;
      foreach my $epitope (keys %{$$epitopes{$seqId}}){

	my ($start, $end) = &_getLocation($$epitopes{$seqId}->{$epitope}->{seq}, $subjSeq);

	if ($start && $end) {
	  $$epitopes{$seqId}->{$epitope}->{start} = $start;
	  $$epitopes{$seqId}->{$epitope}->{end} = $end;
	}else{
	  $foundAll = 0;
	  print STDERR "EPITOPE '$epitope' NOT FOUND IN SEQ '$subId'\n" if($$epitopes{$seqId}->{$epitope}->{blastHit});
	}
      }

      ##output the results into a file that you can load with plugin
      &_printResultsToFile($seqId, $subId, $epitopes, $outFile, $foundAll);
}

sub makeEpitopeHash{
  my ($epitopeFile,$epitopes) = @_;

  print STDERR "Generating epitope hash from file...\n";

  open (FILE, $epitopeFile) || die "Could not open file '$epitopeFile':$!'";

  while (<FILE>){
    chomp;

    my @data = split('\t',$_);

    next if ($data[0] eq 'Accession');

    $$epitopes{$data[0]}->{$data[1]} =  ({seq => $data[3],
					      strain => $data[2],
					      name => $data[4]
					     });
  }
}

sub _getLocation{
  my ($epiSeq, $subSeq) = @_;
  my $start;
  my $end;

  if($subSeq =~ /$epiSeq/i){
    ($start) = @-; #@- holds one before the start of match
    $start ++;
    ($end) = @+; #@+ holds the end of match

  }
return ($start,$end);
}

sub _printResultsToFile{
  my ($seqId, $subId, $epitopes, $outFile, $foundAll) = @_;

  foreach my $iedbId (keys %{$$epitopes{$seqId}}){

      my $name = $epitopes->{$seqId}->{$iedbId}->{name};
      my $start = $epitopes->{$seqId}->{$iedbId}->{start};
      my $end = $epitopes->{$seqId}->{$iedbId}->{end};
      my $strain = $epitopes->{$seqId}->{$iedbId}->{strain};
      my $blastHit = 0;
      if($$epitopes{$seqId}->{$iedbId}->{blastHit}){
	$blastHit = 1;
      }
      my $score = 0;
      if($$epitopes{$seqId}->{$iedbId}->{score}){
	$score = $$epitopes{$seqId}->{$iedbId}->{score};
      }

      if($start && $end){
	open(OUT,">>$outFile") || die "Could not open '$outFile' for appending:$!\n";

	print OUT "$subId\t$iedbId\t$name\t$start\t$end\t$blastHit\t$score\t$foundAll\n";

	close(OUT);

      }
    }
}

1;
