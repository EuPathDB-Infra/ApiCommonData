package ApiCommonData::Load::IntronJunctionsEbi;
use base qw(CBIL::StudyAssayResults::DataMunger::Loadable);

use strict;
use CBIL::Util::V;
use Data::Dumper;

sub getSampleName {$_[0]->{sampleName}}

sub getInputs {$_[0]->{inputs}}
sub getSuffix {$_[0]->{suffix}}
sub getSourceIdPrefix {$_[0]->{sourceIdPrefix}}

sub new {
  my ($class, $args) = @_;

  my $requiredParams = [
                          'sampleName',
                          'inputs',
                          'suffix'
                         ];
  my $self = $class->SUPER::new($args, $requiredParams);


  my $cleanSampleName = $self->getSampleName();
  $cleanSampleName =~ s/\s/_/g; 
  $cleanSampleName=~ s/[\(\)]//g;

  $self->setOutputFile($cleanSampleName . "_results_" . $self->getSuffix());


  return $self;
}

sub munge {
  my ($self) = @_;

  my $inputs = $self->getInputs();
  my $suffix = $self->getSuffix();
  my $sampleName = $self->getSampleName();

  my $outputFile = $self->getOutputFile();

  $self->setNames([$sampleName]);
  $self->setFileNames([$outputFile]);

  my %data;

  foreach my $input (@$inputs) {
    my $inputFile = "$input/$suffix";

    open(INPUT, $inputFile) or die "Cannot open input file $inputFile for reading:$!";

    <INPUT>; #rm header
    while(<INPUT>) {
      chomp;
      my ($junction, $strand, $u, $nu) = split(/\t/, $_);

      my $id = $junction . $strand;

      push @{$data{$id}->{unique}}, $u;
      push @{$data{$id}->{nonunique}}, $nu;
    }

    close INPUT;
  }

  open(OUT, "> $outputFile") or die "Cannot open output file $outputFile for writing:$!";

  print OUT "sequence_source_id\tsegment_start\tsegment_end\tis_reversed\tunique_reads\tnu_reads\n";
  foreach my $key (keys %data) {
    my $averageUnique = CBIL::Util::V::average(@{$data{$key}->{unique}});
    my $averageNonUnique = CBIL::Util::V::average(@{$data{$key}->{nonunique}});

    $key =~ /(.+):(\d+)\-(\d+)(\+|\-)/;

    my $sourceIdPrefix = $self->getSourceIdPrefix();
    my $sequenceSourceId = defined ($sourceIdPrefix) ? "$sourceIdPrefix:$1" : $1;

    my $isReversed = $4 eq '+' ? 0 : 1;

    print OUT "$sequenceSourceId\t$2\t$3\t$isReversed\t$averageUnique\t$averageNonUnique\n";
  }

  close OUT;

  $self->setSourceIdType('segment');
  $self->setInputProtocolAppNodesHash({$sampleName => $inputs});

  $self->createConfigFile();
}


1;
