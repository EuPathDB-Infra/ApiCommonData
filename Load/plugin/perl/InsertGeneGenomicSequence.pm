package ApiCommonData::Load::Plugin::InsertGeneGenomicSequence;

@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;

use GUS::PluginMgr::Plugin;
use FileHandle;

use ApiCommonData::Load::Util;

use GUS::Model::DoTS::ExternalNASequence;
use GUS::Model::ApiDB::GeneGenomicSequence_Split;

my $argsDeclaration =
  [
      stringArg({name => 'dbRlsIds',
              descr => 'genome external database release id',
              reqd => 1,
              isList => 1,
              constraintFunc => undef,
             }),
];

my $purpose = <<PURPOSE;
PURPOSE

my $purposeBrief = <<PURPOSE_BRIEF;

PURPOSE_BRIEF

my $notes = <<NOTES;
NOTES

my $tablesAffected = <<TABLES_AFFECTED;
TABLES_AFFECTED

my $tablesDependedOn = <<TABLES_DEPENDED_ON;
TABLES_DEPENDED_ON

my $howToRestart = <<RESTART;
No Restart utilities for this plugin.
RESTART

my $failureCases = <<FAIL_CASES;
FAIL_CASES

my $documentation = { purpose          => $purpose,
		      purposeBrief     => $purposeBrief,
		      notes            => $notes,
		      tablesAffected   => $tablesAffected,
		      tablesDependedOn => $tablesDependedOn,
		      howToRestart     => $howToRestart,
		      failureCases     => $failureCases };

# ----------------------------------------------------------------------

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self,$class);

  $self->initialize({ requiredDbVersion => 3.5,
		      cvsRevision       => '$Revision$',
		      name              => ref($self),
		      argsDeclaration   => $argsDeclaration,
		      documentation     => $documentation});
  return $self;
}


sub run {
  my ($self) = @_;

  my $dbRlsIds=  $self->getArg('dbRlsIds');
  my $dbh = $self->getQueryHandle();
  my $sql = "select gf.source_id,
             case
              when type = 'exon' and gl.is_reversed = 0
               then substr(s.sequence, gm.start_min, (gm.end_max - gm.start_min) + 1)
              when type = 'exon' and gl.is_reversed = 1
               then apidb.reverse_complement_clob(substr(s.sequence, gm.start_min, (gm.end_max - gm.start_min) + 1))
              when type = 'intron' and gl.is_reversed = 0
               then lower(substr(s.sequence, gm.start_min, (gm.end_max - gm.start_min) + 1))
              else lower(apidb.reverse_complement_clob(substr(s.sequence, gm.start_min, (gm.end_max - gm.start_min) + 1)))
             end as sequence,
             case 
	      when gl.is_reversed = 1 then -1 * gm.start_min 
              else gm.start_min 
             end as start_min
             from dots.GeneFeature gf, dots.nalocation gl, dots.NaSequence s,
             (select 'exon' as type, ef.parent_id as na_feature_id,  el.start_min as start_min, el.end_max as end_max
              from dots.ExonFeature ef, dots.nalocation el
              where ef.na_feature_id = el.na_feature_id
              union
              select 'intron' as type, left.parent_id as na_feature_id, leftLoc.end_max + 1  as start_min, rightLoc.start_min - 1 as end_max
              from dots.ExonFeature left, dots.nalocation leftLoc,  dots.ExonFeature right, dots.nalocation rightLoc
              where left.parent_id = right.parent_id
              and (left.order_number = right.order_number - 1 or left.order_number = right.order_number + 1)
              and leftLoc.start_min < rightLoc.start_min
              and left.na_feature_id = leftLoc.na_feature_id
              and right.na_feature_id = rightLoc.na_feature_id ) gm
          where gm.na_feature_id = gf.na_feature_id
          and s.na_sequence_id = gf.na_sequence_id
          and gf.na_feature_id = gl.na_feature_id
          and gf.external_database_release_id in ($dbRlsIds)";


  my $sh = $dbh->prepare($sql);
  $sh->execute();

  while(my ($source_id, $gene_genomic_sequence, $start_min) = $sh->fetchrow_array()) {
     my $profile = GUS::Model::ApiDB::GeneGenomicSequence_Split->
	      new({source_id => $source_id,
		   gene_genomic_sequence => $gene_genomic_sequence,
		   start_min => $start_min
		   });
	  $profile->submit();
  }
}

sub undoTables {
  my ($self) = @_;

  return ('ApiDB.GeneGenomicSequence_Split',
	 );
}
1;

