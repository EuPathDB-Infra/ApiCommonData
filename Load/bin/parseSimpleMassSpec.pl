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
#^^^^^^^^^^^^^^^^^^^^^^^^^ End GUS4_STATUS ^^^^^^^^^^^^^^^^^^^^
use lib "$ENV{GUS_HOME}/lib/perl";

use strict;

use CBIL::Util::PropertySet;

use Getopt::Long;

use ApiCommonData::Load::MassSpecTransform;

use Data::Dumper;

my ($help, $file, $config, $debug, $out);

&GetOptions('help|h' => \$help,
            'data_file=s' => \$file,
            'output_file=s' => \$out,
            'config_file=s' => \$config,
            'debug' => \$debug,
    );


my @properties = (#["proteinIdColumn"],
                  #["geneSourceIdColumn"],
                  #["peptideSequenceColumn"],
                  #["peptideSpectrumColumn"],
                  #["peptideIonScoreColumn"],
                  ["class", "ApiCommonData::Load::MassSpecTransform"],
                  ["delimiter","\t"],
                  ["trimPeptideRegex", '^[\w-]*\.(.+)\.[\w-]*$'],
                  ["skipLines"],
                  ["headerRegex"],
    );


if($help) {
  &usage();
  exit;
}


my $prop = CBIL::Util::PropertySet->new($config, \@properties, 1);

my $trimPeptideRegex = qr /$prop->{props}->{trimPeptideRegex}/;
my $headerRegex = qr /$prop->{props}->{headerRegex}/;
my $delimiter = qr/$prop->{props}->{delimiter}/;

my $args = {proteinIdColumn => $prop->{props}->{proteinIdColumn},
            geneSourceIdColumn => $prop->{props}->{geneSourceIdColumn},
            peptideSequenceColumn => $prop->{props}->{peptideSequenceColumn},
            peptideSpectrumColumn => $prop->{props}->{peptideSpectrumColumn},
            peptideIonScoreColumn => $prop->{props}->{peptideIonScoreColumn},
            skipLinesCount => $prop->{props}->{skipLines},
            delimiter => $delimiter,
            trimPeptideRegex => $trimPeptideRegex,
            headerRegex => $headerRegex,
            inputFile => $file,
            outputFile => $out,
            debug => $debug
};

my $class = $prop->{props}->{class};

eval "require $class";

my $mst = eval {
    $class->new($args);
  };

die "Could not create class $class" if $@;


$mst->readFile();

$mst->writeFile();



sub usage {
  print "usage:  parseSimpleMassSpec.pl -data_file <INPUT> -output_file <OUTPUT> -config_file <CONFIG> [-debug]\n\n";

  print "SAMPLE PROP FILE:

# required column is 0 based
skipLines=2   skip lines at beginning of input file that are not header or data
headerRegex=TriTrypDB accession number

# required but prompted 
proteinIdColumn= column # for actual protein ids or ,if no protein ids, column for gene ids (same as geneSourceIdColumn if gene Ids) 
geneSourceIdColumn= 
peptideSequenceColumn=
peptideSpectrumColumn=
peptideIonScoreColumn=

# override defaults only if needed
class=  appropriate package in ApiCommonData::Load::MassSpecTransform
delimiter=
trimPeptideRegex=

";
  
}

1;


