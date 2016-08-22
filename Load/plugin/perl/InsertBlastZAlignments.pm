package ApiCommonData::Load::Plugin::InsertBlastZAlignments;
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
@ISA = qw( GUS::PluginMgr::Plugin);

use strict;
use warnings;

use GUS::PluginMgr::Plugin;

use GUS::Model::DoTS::Similarity;
use GUS::Model::DoTS::SimilaritySpan;

use List::Util qw(min max sum);

my $argsDeclaration = 
  [
   fileArg({ name           => 'inputFile',
	     descr          => 'BlastZ output (in LAV format)',
	     reqd           => 1,
	     mustExist      => 1,
	     format         => 'LAV',
	     constraintFunc => undef,
	     isList         => 0,
	   }),

   stringArg({name => 'queryTable',
	      descr => 'where do we find the query sequences',
	      constraintFunc => undef,
	      reqd => 1,
	      isList => 0
	     }),

   stringArg({name => 'subjTable',
	      descr => 'where do we find the subject sequences',
	      constraintFunc => undef,
	      reqd => 1,
	      isList => 0
	     }),

   stringArg({name => 'queryExtDbRlsSpec',
	      descr => 'where do we find source_id\'s for the queries',
	      constraintFunc => undef,
	      reqd => 1,
	      isList => 0
	     }),

   stringArg({name => 'subjExtDbRlsSpec',
	      descr => 'where do we find source_id\'s for the subjects',
	      constraintFunc => undef,
	      reqd => 1,
	      isList => 0
	     }),

  ];

my $purposeBrief = <<PURPOSEBRIEF;
PURPOSEBRIEF

my $purpose = <<PLUGIN_PURPOSE;
PLUGIN_PURPOSE

my $tablesAffected = <<TABLES_AFFECTED;
TABLES_AFFECTED

my $tablesDependedOn = [];

my $howToRestart = <<PLUGIN_RESTART;
PLUGIN_RESTART

my $failureCases = <<PLUGIN_FAILURE_CASES;
PLUGIN_FAILURE_CASES

my $notes = <<PLUGIN_NOTES;
PLUGIN_NOTES

my $documentation = { purpose=>$purpose,
		      purposeBrief=>$purposeBrief,
		      tablesAffected=>$tablesAffected,
		      tablesDependedOn=>$tablesDependedOn,
		      howToRestart=>$howToRestart,
		      failureCases=>$failureCases,
		      notes=>$notes
		    };

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self,$class);

  $self->initialize({ requiredDbVersion => 3.6,
		      cvsRevision => '$Revision$',
		      name => ref($self),
		      argsDeclaration => $argsDeclaration,
		      documentation => $documentation
		    });

  return $self;
}

sub run {

  my ($self) = @_;

  my $file = $self->getArg('inputFile');

  my $queryExtDbRlsId = $self->getExtDbRlsId($self->getArg('queryExtDbRlsSpec'));
  my $subjExtDbRlsId = $self->getExtDbRlsId($self->getArg('subjExtDbRlsSpec'));

  my $queryTable = $self->getArg('queryTable');
  my $subjTable = $self->getArg('subjTable');

  my $queryTableId = $self->className2TableId($queryTable);
  my $subjTableId = $self->className2TableId($subjTable);

  $queryTable = "GUS::Model::$queryTable";
  $subjTable = "GUS::Model::$subjTable";

  open(IN, "<$file") or $self->error("Couldn't open file '$file': $!\n");

  my $header = <IN>;
  $self->error("Doesn't look like $file is in LAV format!")
    unless $header =~ m/^\#:lav/i;

  my $context;
  my %handler = ( s => sub {
                    $context = shift;
		    my ($query, $subject) = @_;
		    ($context->{queryLen}, $context->{queryIsReversed}) = $query =~ m/(\d+)\s+([01])\s+\d+\s*$/;

		    ($context->{subjLen}, $context->{subjIsReversed}) = $subject =~ m/(\d+)\s+([01])\s+\d+\s*$/;
		  },

		  a => sub {
		    $self->_processSimilarity($queryTableId, $subjTableId, @_);
		  },

		  h => sub {
		    my ($context, $query, $subject) = @_;
		    my ($querySourceId) = $query =~ m/>(\S+)/;
		    my ($subjSourceId) = $subject =~ m/>(\S+)/;
		    $context->{queryId} = $self->_getSeqId($querySourceId,
							   $queryTable,
							   $queryExtDbRlsId);
		    $context->{subjId} = $self->_getSeqId($subjSourceId,
							  $subjTable,
							  $subjExtDbRlsId);
		  },
		);

  OUTER : while (<IN>) {

    if (m/^\#:lav/) {
      # do nothing, format header
    } elsif (m/^([dshaxm])\s+\{/) {
      my $blockType = $1;

      my $buffer = "";
      INNER : while (<IN>) {
	last INNER if m/^\}/;
	$buffer .= $_;
      }

      $handler{$blockType}->($context, split("\n", $buffer))
	if exists $handler{$blockType};
    }
  }

  return "done (inserted $context->{count} similarities)";
}

sub _getSeqId {

  my ($self, $sourceId, $tableName, $extDbRlsId) = @_;

  return $self->{_seqIdCache}->{$tableName}->{$extDbRlsId}->{$sourceId} ||= do {
    eval "require $tableName"; $self->error($@) if $@;

    my $seq = $tableName->new({ source_id => $sourceId,
				external_database_release_id => $extDbRlsId,
			      });
    unless ($seq->retrieveFromDB()) {
      $self->error("Couldn't find a $tableName with id of $sourceId");
    }
    $seq->getId();
  }
}

sub _processSimilarity {

  my ($self, $queryTableId, $subjTableId,
      $context, $score, $begin, $end, @hsps) = @_;

  my ($queryStart, $queryEnd, $subjStart, $subjEnd);

  ($score) = $score =~ m/s\s+(\d+)/;
  
  @hsps = map {
    my $hsp;
    @{$hsp}{qw(queryStart subjStart queryEnd subjEnd percId)} =
      $_ =~ m/^\s+l\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/;
    $hsp->{alnLen} = $hsp->{queryEnd} - $hsp->{queryStart} + 1;
    $hsp->{isReversed} = ($context->{queryIsReversed} || $context->{subjIsReversed});

    # recalculate coordinates on + strand, if necessary:
    if ($context->{queryIsReversed}) {
      $hsp->{queryEnd}   = $hsp->{queryLen} - $hsp->{queryStart} + 1;
      $hsp->{queryStart} = $hsp->{queryLen} - $hsp->{queryEnd}   + 1;
    }

    # recalculate coordinates on + strand, if necessary:
    if ($context->{subjIsReversed}) {
      $hsp->{subjEnd}   = $hsp->{subjLen} - $hsp->{subjStart} + 1;
      $hsp->{subjStart} = $hsp->{subjLen} - $hsp->{subjEnd}   + 1;
    }

    if ($queryStart){
      $queryStart = min($queryStart, $hsp->{queryStart});
    }else{
      $queryStart = $hsp->{queryStart};
    }

    if ($queryEnd){
      $queryEnd = min($queryEnd, $hsp->{queryEnd});
    }else{
      $queryEnd = $hsp->{queryEnd};
    }

    if ($subjStart){
      $subjStart = min($subjStart, $hsp->{subjStart});
    }else{
      $subjStart = $hsp->{subjStart};
    }

    if ($subjEnd){
      $subjEnd = min($subjEnd, $hsp->{subjEnd});
    }else{
      $subjEnd = $hsp->{subjEnd};
    }

    $hsp;

  } @hsps;

  @hsps = sort { $a->{queryStart} <=> $b->{queryStart} } @hsps;

  my $sim =
    GUS::Model::DoTS::Similarity->new(
     {
      subject_table_id   => $subjTableId,
      subject_id         => $context->{subjId},
      query_table_id     => $queryTableId,
      query_id           => $context->{queryId},
      min_subject_start  => $subjStart,
      max_subject_end    => $subjEnd,
      min_query_start    => $queryStart,
      max_query_end      => $queryEnd,
      number_of_matches  => scalar(@hsps),
      total_match_length => sum(map { $_->{alnLen} } @hsps),
      number_identical   => sprintf("%d", sum(map { $_->{percId} * $_->{alnLen} } @hsps)),
      number_positive    => sprintf("%d", sum(map { $_->{percId} * $_->{alnLen} } @hsps)),
      is_reversed        => ($context->{queryIsReversed} || $context->{subjIsReversed}),
      score              => $score,
     });

  for my $hsp (@hsps) {
    my $simSpan =
      GUS::Model::DoTS::SimilaritySpan->new(
       {
	match_length => $hsp->{alnLen},
	number_identical => sprintf("%d", $hsp->{alnLen} * $hsp->{percId}),
	number_positive => sprintf("%d", $hsp->{alnLen} * $hsp->{percId}),
	subject_start => $hsp->{subjStart},
	subject_end => $hsp->{subjEnd},
	query_start => $hsp->{queryStart},
	query_end => $hsp->{queryEnd},
	is_reversed => $hsp->{isReversed},
       });
    $sim->addChild($simSpan);
  }

  $sim->submit();
  $self->undefPointerCache();
}

sub undoTables {
  return qw( DoTS.SimilaritySpan
	     DoTS.Similarity
	   );
}

1;
