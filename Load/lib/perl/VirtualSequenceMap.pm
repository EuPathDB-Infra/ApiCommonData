package ApiCommonData::Load::VirtualSequenceMap;
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

use Bio::Coordinate::Collection;
use Bio::Coordinate::Pair;
use Bio::Location::Simple;

sub new {

  my ($class, $args) = @_;

  $class = ref $class || $class;
  my $self = bless {}, $class;

  $self->{_mapper} = Bio::Coordinate::Collection->new();

  my ($extDbRlsId, $virtExtDbRlsId, $dbh) = @$args{qw(extDbRlsId virtDbRlsId dbh)};

  my $sth = $dbh->prepare(<<EOSQL);

  SELECT vs.source_id,
         nas.source_id,
         nas.length, -- requires that LENGTH field be filled!!
         sp.distance_from_left,
	 sp.strand_orientation

  FROM   DoTS.SequencePiece   sp,
         DoTS.VirtualSequence vs,
         Dots.ExternalNASequence      nas

  WHERE  sp.virtual_na_sequence_id = vs.na_sequence_id
    AND  sp.piece_na_sequence_id = nas.na_sequence_id

    AND  vs.external_database_release_id = ?
    AND  nas.external_database_release_id = ?

  ORDER BY vs.source_id ASC,
           sp.sequence_order ASC
EOSQL

  $sth->execute($virtExtDbRlsId, $extDbRlsId);

  my $lastVirtualSequenceId;
  my $offset = 0;
  while (my ($virtualSequenceId, $sequenceId,
	     $length, $distanceFromLeft, $orientation) = $sth->fetchrow_array()) {

    if ($orientation eq '0'){
      $orientation = '+1';
    }

    if (defined($lastVirtualSequenceId) && $lastVirtualSequenceId ne $virtualSequenceId) {
      $offset = 0;
    }

    $lastVirtualSequenceId = $virtualSequenceId;

    $offset += $distanceFromLeft;

    $self->{_mapper}->add_mapper(
      Bio::Coordinate::Pair->new(-in => Bio::Location::Simple->new( -seq_id => $sequenceId,
								    -start => 1,
								    -end => $length,
								    -strand => +1,
								  ),
				 -out => Bio::Location::Simple->new( -seq_id => $virtualSequenceId,
								     -start => $offset + 1,
								     -end => $offset + $length,
								     -strand => $orientation,
								   ),
				)
    );

    $offset += $length;

  }

  return $self;
}

sub map {
  my $self = shift;
  return $self->{_mapper}->map(@_);
}

1;
