package ApiCommonData::Load::Plugin::InsertPARIntronJunctions;

@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;

use lib "$ENV{GUS_HOME}/lib/perl";

use DBI;
use DBD::Oracle;
use GUS::Model::ApiDB::IntronJunction;
use GUS::PluginMgr::Plugin;
use GUS::Model::DoTS::NASequence;
use Bio::Location::Simple;
use Bio::Coordinate::Pair;
use Data::Dumper;

# ----------------------------------------------------------
# Load Arguments
# ----------------------------------------------------------

my $argsDeclaration  =
  [
   fileArg({name           => 'mappingFile',
            descr          => 'file containing mapping of pseudoautosomal regions',
            reqd           => 1,
            mustExist      => 1,
            format         => '',
            constraintFunc => undef,
            isList         => 0, }),
  ];

# ----------------------------------------------------------
# Documentation
# ----------------------------------------------------------

  my $description = <<DESCR;
Lift over features in pseudoautosomal regions.
DESCR

  my $purpose = <<PURPOSE;
Lift over features in pseudoautosomal regions.
PURPOSE

  my $purposeBrief = <<PURPOSEBRIEF;
Lift over features in pseudoautosomal regions.
PURPOSEBRIEF

  my $notes = <<NOTES;
NOTES

  my $tablesAffected = <<AFFECT;
ApiDB.IntronJunction
AFFECT

  my $tablesDependedOn = <<TABD;
TABD

  my $howToRestart = <<RESTART;
No restart provided. Undo and re-run.
RESTART

  my $failureCases = <<FAIL;
FAIL

  my $documentation = { purpose          => $purpose,
			purposeBrief     => $purposeBrief,
			tablesAffected   => $tablesAffected,
			tablesDependedOn => $tablesDependedOn,
			howToRestart     => $howToRestart,
			failureCases     => $failureCases,
			notes            => $notes
		      };


sub new {
  my ($class) = @_;
  my $self = {};
  bless($self, $class);

  $self->initialize ({ requiredDbVersion => 4.0,
			cvsRevision => '$Revision$',
			name => ref($self),
			argsDeclaration => $argsDeclaration,
			documentation => $documentation
		      });

  $self->{insertCount} = 0;
  return $self;
}

sub run {
  my ($self) = @_;

  my $dbh = $self->getQueryHandle();

  my $queryStmt = $dbh->prepare(<<SQL) or die $dbh->errstr;
   select protocol_app_node_id, segment_start, segment_end,
          is_reversed, unique_reads, nu_reads
   from apidb.IntronJunction
   where na_sequence_id
         = (select na_sequence_id
            from dots.NaSequence
            where source_id = ?
           )
     and segment_end >= ?
     and segment_start <= ?
   order by segment_start, segment_end
SQL

  my $mappingFile = "parMap.dat";

  open (my $fh, "<", $mappingFile) or die "can't open file \"$mappingFile\"";
  while (<$fh>) {
    my ($fromId, $fromStart, $fromEnd, $toId, $toStart, $toEnd);

    # parse location mapping
    if ($_ =~ "(.*):(.*)-(.*)\t(.*):(.*)-(.*)\n") {
      $toId = $1;
      $toStart = $2;
      $toEnd = $3;
      $fromId = $4;
      $fromStart = $5;
      $fromEnd = $6;
      # print "from $fromId at $fromStart to $fromEnd onto $toId at $toStart to $toEnd is my mapping\n";
    } else {
      die "could not parse mapping \"$_\"";
    }

    # get na_sequence_id
    my $naSequence
      = GUS::Model::DoTS::NASequence->new({ source_id => $toId });
    $naSequence->retrieveFromDB();

    # make mapping
    my $fromRegion = Bio::Location::Simple->new( -seq_id => $fromId,
						 -start => $fromStart,
						 -end =>  $fromEnd,
						 -strand => '+1' );

    my $toRegion = Bio::Location::Simple->new( -seq_id => $toId,
					       -start => $toStart,
					       -end =>  $toEnd,
					       -strand => '+1' );

    my $agp = Bio::Coordinate::Pair->new( -in  => $fromRegion, -out => $toRegion );

    # find all features in "from" region
    $queryStmt->execute($fromId, $fromStart, $fromEnd) or die $dbh->errstr;
    while (my ($protocolAppNodeId, $segmentStart, $segmentEnd, $isReversed,
               $uniqueReads, $nuReads)
	   = $queryStmt->fetchrow_array()) {

      # print "got $featureType $featureSourceId\n";

      my $unmappedFeature = Bio::Location::Simple->
	new( -seq_id => $fromId, -start =>   $segmentStart, -end =>  $segmentEnd,
	     -strand => $isReversed ? "-1" : "+1" );
      my $mappedFeature = $agp->map($unmappedFeature);

      my $intronJunction
	= GUS::Model::ApiDB::IntronJunction->new({
						   protocol_app_node_id => $protocolAppNodeId,
						   is_reversed => $isReversed,
						   unique_reads => $uniqueReads,
						   nu_reads => $nuReads,
						   na_sequence_id => $naSequence->getId(),
						   segment_start => $mappedFeature->start,
						   segment_end => $mappedFeature->end,
						  });

      $intronJunction->submit() unless ($intronJunction->retrieveFromDB());
    }

    $queryStmt->finish() or die $dbh->errstr;

  }
  close $fh;

  my $status = "inserted " . $self->{insertCount} . " records";
  return $status
}


sub undoTables {
  return ('ApiDB.IntronJunction',
	 );
}
