package ApiCommonData::Load::TranscriptAndExonCdsUtr2BioperlTree;
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


use strict;
use Bio::SeqFeature::Generic;
use Bio::Location::Simple;
use ApiCommonData::Load::BioperlTreeUtils qw{makeBioperlFeature};

#input: CDS with join location (if multiple exons)
#output: standard api tree: gene->transcript->exons
#                      ->CDS

sub preprocess {
    my ($bioperlSeq, $plugin) = @_;

    foreach my $bioperlFeatureTree ($bioperlSeq->get_SeqFeatures()) {

        my $type = $bioperlFeatureTree->primary_tag();

        if ( $type eq 'transcript' ) {

            $type = "coding";
            $bioperlFeatureTree->primary_tag("${type}_gene");

            my $gene = $bioperlFeatureTree;
            my $geneLoc = $gene->location();
             
            my $transcript = &makeBioperlFeature("transcript", $geneLoc, $bioperlSeq);

            ## the original exon feature need to be removed
            ## before transcript add exon
            my @exons = $gene->remove_SeqFeatures();

            my ($codingStart, $codingEnd);
            foreach my $exon (@exons) {
                if ($exon->location->strand == -1) {
                    $codingStart = $exon->location->end;
                    $codingEnd = $exon->location->start;
                    $codingStart -= $exon->frame() if ($exon->frame() > 0);
                } else {
                    $codingStart = $exon->location->start;
                    $codingEnd = $exon->location->end;
                    $codingStart += $exon->frame() if ($exon->frame() > 0);
                }
                $exon->remove_tag("CodingStart");
                $exon->remove_tag("CodingEnd");
                $exon->add_tag_value('CodingStart', $codingStart);
                $exon->add_tag_value('CodingEnd', $codingEnd);

                #my $t = $exon->primary_tag();
                #die "expected bioperl exon but got '$t'" unless $t = "exon";

                # the frame loade to gus will be 1,2 or 3
                my $frame = $exon->frame();
                if($frame =~ /[012]/) {
                    $frame++;
                    $exon->add_tag_value('reading_frame', $frame);
                }

                $transcript->add_SeqFeature($exon);
            }
            
            # we have to remove the exons before adding the transcript b/c
            # remove_SeqFeatures() removes all subfeatures of the $gene
            #$gene->remove_SeqFeatures();
            $gene->add_SeqFeature($transcript);
        }
    }
}


1;

