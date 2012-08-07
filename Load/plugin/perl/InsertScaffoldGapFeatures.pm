package ApiCommonData::Load::Plugin::InsertScaffoldGapFeatures;

@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;

use GUS::PluginMgr::Plugin;
use GUS::Model::DoTS::ScaffoldGapFeature;
use GUS::Model::DoTS::NALocation;
use GUS::Model::SRes::SequenceOntology;


sub getArgsDeclaration {
my $argsDeclaration  =
[

stringArg({name => 'extDbRlsName',
       descr => 'List of External Database names for the scaffolds or chromosomes',
       constraintFunc=> undef,
       reqd  => 1,
       isList => 1
      }),

stringArg({name => 'extDbRlsVer',
       descr => 'List of version of each External Database, corresponding to the names',
       constraintFunc=> undef,
       reqd  => 1,
       isList => 1
      }),

stringArg({name => 'SOTerm',
       descr => 'SO term for the gap',
       constraintFunc=> undef,
       reqd  => 0,
       isList => 0,
       default => "gap",
      }),
];

return $argsDeclaration;
}


# ----------------------------------------------------------
# Documentation
# ----------------------------------------------------------

sub getDocumentation {

my $description = <<NOTES;
NOTES

my $purpose = <<PURPOSE;
To load gap info for scaffolds and chromosomes into the database.
PURPOSE

my $purposeBrief = <<PURPOSEBRIEF;
For every scaffold and every chromosome, the plugin find the positions of the gaps, and loads this info the ScaffoldGapFeature and NALocation tables.
PURPOSEBRIEF

my $syntax = <<SYNTAX;
SYNTAX

my $notes = <<NOTES;
NOTES

my $tablesAffected = <<AFFECT;
AFFECT

my $tablesDependedOn = <<TABD;
TABD

my $howToRestart = <<RESTART;
RESTART

my $failureCases = <<FAIL;
FAIL

my $documentation = {purpose=>$purpose, purposeBrief=>$purposeBrief,tablesAffected=>$tablesAffected,tablesDependedOn=>$tablesDependedOn,howToRestart=>$howToRestart,failureCases=>$failureCases,notes=>$notes};

return ($documentation);
}


sub new {
  my $class = shift;
  my $self = {};
  bless($self, $class);
  bless($self, $class);

  my $documentation = &getDocumentation();

  my $args = &getArgsDeclaration();

  my $configuration = {requiredDbVersion => 3.6,
		       cvsRevision => '$Revision: 24153 $',
		       cvsTag => '$Name$',
		       name => ref($self),
		       revisionNotes => '',
		       argsDeclaration => $args,
		       documentation => $documentation
		      };
  $self->initialize($configuration);

  return $self;
}


sub run {
  my $self = shift;

  my $SOTermArg = $self->getArg("SOTerm");
  my $SOTerm = GUS::Model::SRes::SequenceOntology->new({ term_name => $SOTermArg });
  unless($SOTerm->retrieveFromDB()) {
    die "SO Term $SOTerm not found in database.\n";
  }
  my $SOTermId = $SOTerm->getId();

  # the array of External Database Names and their corresponding versions
  my @extDbNameArr = @{$self->getArg('extDbRlsName')};
  my @extDbVerArr  = @{$self->getArg('extDbRlsVer')};

  for (my $i=0; $i<=$#extDbNameArr; $i++) {
    my $extDbName = $extDbNameArr[$i];
    my $extDbVer  = $extDbVerArr[$i];
    my $extDbRlsId = $self->getExtDbRlsId($extDbName, $extDbVer)
      or die "Couldn't find source db: $extDbName, $extDbVer\n";
    $self->log("External Database Name: $extDbName, Version: $extDbVer, ReleaseID: $extDbRlsId");


    # retrieve sequences in a hash
    my $seqsRef = $self->retrieveSequences($extDbRlsId);

    # create a feature for each gap
    my $ct = $self->makeGapFeatureAssignments($seqsRef, $extDbRlsId, $SOTermArg, $SOTermId);
    $self->log("$ct gap features created for $extDbName.");
  }
  return("Gap Features loaded");
}


# retrieve scaffold or contig sequences in a hash
sub retrieveSequences {
  my ($self, $extDbRlsId) = @_;

  my $dbh = $self->getQueryHandle();
  my %allSeqs;

  my $stmt = $dbh->prepare("SELECT na_sequence_id, sequence FROM DoTS.NASequence WHERE external_database_release_id =?");
  $stmt->execute($extDbRlsId);

  while(my ($na_seq_id, $seq) = $stmt->fetchrow_array()) {
    $allSeqs{$na_seq_id}=$seq;
  }

  $self->undefPointerCache();
  return(\%allSeqs);
}


sub makeGapFeatureAssignments {
  my ($self, $scaffRef, $extDbRlsId, $termName, $seqOntId) = @_;

  my $count=0;
  my %map = %{$scaffRef};
  my @keyed = keys(%map);  # array of sequence IDs
  $self->log("Number of sequences = ".($#keyed+1));

  # for each sequence
  foreach my $key (@keyed) {
    my $seq = $map{$key};
    my $prev_pos = 0;
    my $pos;

    # for each gap
    while( $seq =~ m/(NNN*)/gi){
      my $gapSize = length($1);

      # find gap position, and create row in ScaffoldGapFeature + NALocation
      $pos = index ($seq, $1, $prev_pos) + 1;
      my $scaffGap = $self->createScaffoldGapEntry($key, $extDbRlsId, $gapSize, $termName, $seqOntId);
      my $naLocation = $self->createNaLocation($pos, ($pos + $gapSize - 1));

      $$scaffGap->addChild($$naLocation);
      $$scaffGap->submit();
      $count++;

      $prev_pos = $pos + $gapSize;
    }
  }
  return $count;
}


sub createScaffoldGapEntry{
  my ($self, $naSeqId, $extDbRlsId, $gapSize, $termName, $seqOntId) = @_;

  my $scaffGap = GUS::Model::DoTS::ScaffoldGapFeature->new({na_sequence_id => $naSeqId,
							    name => $termName,
							    sequence_ontology_id => $seqOntId,
							    external_database_release_id => $extDbRlsId,
							    min_size => $gapSize,
							    max_size => $gapSize,
							   });
  return \$scaffGap;
}

sub createNaLocation{
  my ($self, $start, $end) = @_;

  my $naLocation = GUS::Model::DoTS::NALocation->new({start_min => $start,
						      start_max => $start,
						      end_min => $end,
						      end_max => $end,
						     });
  return \$naLocation;

}


sub undoTables {
  my ($self) = @_;

  return ('DoTS.NALocation',
          'DoTS.ScaffoldGapFeature'
         );
}


1;
