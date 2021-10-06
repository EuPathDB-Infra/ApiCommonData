package ApiCommonData::Load::Plugin::LoadEntityTypeAndAttributeGraphs;

@ISA = qw(GUS::PluginMgr::Plugin ApiCommonData::Load::Plugin::ParameterizedSchema);
use strict;
use warnings;
use GUS::PluginMgr::Plugin;
use ApiCommonData::Load::Plugin::ParameterizedSchema;

use ApiCommonData::Load::StudyUtils qw(queryForOntologyTerms);

my $purposeBrief = 'Read ontology and study tables and insert tables which store parent child relationships for entitytypes and attributes';
my $purpose = $purposeBrief;

my $tablesAffected =
    [ ['__SCHEMA__::AttributeGraph', ''],
      ['__SCHEMA__::EntityTypeGraph', '']
    ];

# TODO
my $tablesDependedOn =
    [['__SCHEMA__::Study',''],
     ['__SCHEMA__::EntityAttributes',  ''],
     ['__SCHEMA__::ProcessAttributes',  ''],
     ['__SCHEMA__::ProcessType',  ''],
     ['__SCHEMA__::EntityType',  ''],
     ['__SCHEMA__::AttributeUnit',  ''],
     ['SRes::OntologyTerm',  ''],
     ['__SCHEMA__::ProcessType',  ''],
    ];

my $howToRestart = ""; 
my $failureCases = "";
my $notes = "";

my $documentation = { purpose => $purpose,
                      purposeBrief => $purposeBrief,
                      tablesAffected => $tablesAffected,
                      tablesDependedOn => $tablesDependedOn,
                      howToRestart => $howToRestart,
                      failureCases => $failureCases,
                      notes => $notes
};

my $argsDeclaration =
[
   fileArg({name           => 'logDir',
            descr          => 'directory where to log sqlldr output',
            reqd           => 1,
            mustExist      => 1,
            format         => '',
            constraintFunc => undef,
            isList         => 0, }),

 stringArg({ name            => 'extDbRlsSpec',
	     descr           => 'ExternalDatabaseSpec for the Entity Graph',
	     reqd            => 1,
	     constraintFunc  => undef,
	     isList          => 0 }),

 stringArg({ name            => 'ontologyExtDbRlsSpec',
	     descr           => 'ExternalDatabaseSpec for the Associated Ontology',
	     reqd            => 1,
	     constraintFunc  => undef,
	     isList          => 0 }),
   stringArg({name           => 'schema',
            descr          => 'GUS::Model schema for entity tables',
            reqd           => 1,
            constraintFunc => undef,
            isList         => 0, }),

];

my $SCHEMA = '__SCHEMA__'; # must be replaced with real schema name
my @UNDO_TABLES = qw(
  AttributeGraph
  EntityTypeGraph
);
my @REQUIRE_TABLES = qw(
  AttributeGraph
  EntityTypeGraph
);

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self,$class);

  $self->initialize({requiredDbVersion => 4.0,
		     cvsRevision => '$Revision$', # cvs fills this in!
		     name => ref($self),
		     argsDeclaration   => $argsDeclaration,
		     documentation     => $documentation
		    });
  $self->{_require_tables} = \@REQUIRE_TABLES;
  $self->{_undo_tables} = \@UNDO_TABLES;
  return $self;
}


$| = 1;

sub run {
  my $self  = shift;

  ## ParameterizedSchema
  $self->requireModelObjects();
  $self->resetUndoTables(); # for when logRowsInserted() is called after loading
  $SCHEMA = $self->getArg('schema');
  ## 

  chdir $self->getArg('logDir');

  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  
  my $studies = $self->sqlAsDictionary( Sql  => "select study_id, max_attr_length from $SCHEMA.study where external_database_release_id = $extDbRlsId");

  $self->error("Expected one study row.  Found ". scalar keys %{$studies}) unless(scalar keys %$studies == 1);

  $self->getQueryHandle()->do("alter session set nls_date_format = 'yyyy-mm-dd hh24:mi:ss'") or die $self->getQueryHandle()->errstr;

  my ($attributeGraphCount, $entityTypeGraphCount);
  while(my ($studyId, $maxAttrLength) = each (%$studies)) {
    my $ontologyTerms = &queryForOntologyTerms($self->getQueryHandle(), $self->getExtDbRlsId($self->getArg('ontologyExtDbRlsSpec')));
    my $allTerms = $self->addNonOntologicalLeaves($ontologyTerms, $studyId);

    $attributeGraphCount += $self->constructAndSubmitAttributeGraphsForOntologyTerms($studyId, $allTerms);

    $entityTypeGraphCount += $self->constructAndSubmitEntityTypeGraphsForStudy($studyId);
  }

  return "Loaded $attributeGraphCount rows into $SCHEMA.AttributeGraph and $entityTypeGraphCount rows into $SCHEMA.EntityTypeGraph";
}


sub addNonOntologicalLeaves {
  my ($self, $terms, $studyId) = @_;

  my $sql = "select distinct a.stable_id as source_id, a.parent_ontology_term_id, pt.source_id as parent_source_id, a.display_name
from $SCHEMA.attribute a, $SCHEMA.entitytype et, sres.ontologyterm pt
where a.entity_type_id = et.entity_type_id
and a.parent_ontology_term_id = pt.ontology_term_id
and et.study_id = ?
and a.ontology_term_id is null";

  my $dbh = $self->getQueryHandle();
  my $sh = $dbh->prepare($sql);
  $sh->execute($studyId);


  while(my $hash = $sh->fetchrow_hashref()) {
    my $sourceId = $hash->{SOURCE_ID};

    if($terms->{$sourceId}) {
      $self->log("WARNING: Stable Id $sourceId found in BOTH ontology AND nonontological leaf; using parent relation from the latter");
    }

    $terms->{$sourceId} = $hash;
  }
  $sh->finish();

  return $terms;
}


sub constructAndSubmitAttributeGraphsForOntologyTerms {
  my ($self, $studyId, $ontologyTerms) = @_;

  my $attributeGraphCount;

  foreach my $sourceId (keys %$ontologyTerms) {
    my $ontologyTerm = $ontologyTerms->{$sourceId};
    
    my $attributeGraph = $self->getGusModelClass('AttributeGraph')->new({study_id => $studyId,
                                                                 ontology_term_id => $ontologyTerm->{ONTOLOGY_TERM_ID},
                                                                 stable_id => $sourceId,
                                                                 parent_stable_id => $ontologyTerm->{PARENT_SOURCE_ID},
                                                                 parent_ontology_term_id => $ontologyTerm->{PARENT_ONTOLOGY_TERM_ID},
                                                                 provider_label => $ontologyTerm->{PROVIDER_LABEL},
                                                                 display_name => $ontologyTerm->{DISPLAY_NAME}, 
                                                                 display_type => $ontologyTerm->{DISPLAY_TYPE}, 
                                                                 display_range_min => $ontologyTerm->{DISPLAY_RANGE_MIN},
                                                                 display_range_max => $ontologyTerm->{DISPLAY_RANGE_MAX},
                                                                 bin_width_override => $ontologyTerm->{BIN_WIDTH_OVERRIDE},
                                                               #  is_hidden => $ontologyTerm->{IS_HIDDEN},
                                                                 is_temporal => $ontologyTerm->{IS_TEMPORAL},
                                                                 is_featured => $ontologyTerm->{IS_FEATURED},
                                                                 is_repeated => $ontologyTerm->{IS_REPEATED},
                                                                 is_merge_key => $ontologyTerm->{IS_MERGE_KEY},
                                                                 display_order => $ontologyTerm->{DISPLAY_ORDER},
                                                                 definition => $ontologyTerm->{DEFINITION},
                                                                 ordinal_values => $ontologyTerm->{ORDINAL_VALUES},
                                                                });
    $attributeGraph->submit();
    $attributeGraphCount++;
  }

  return $attributeGraphCount;
}




sub constructAndSubmitEntityTypeGraphsForStudy {
  my ($self, $studyId) = @_;

  my $dbh = $self->getQueryHandle();
  $dbh->{FetchHashKeyName} = 'NAME_lc';

  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('ontologyExtDbRlsSpec'));

  my $sql = "select et.parent_id
                  , et.parent_stable_id
                  , nvl(os.ontology_synonym, t.name) display_name
                  , t.entity_type_id
                  , t.internal_abbrev
                  ,  ot.source_id as stable_id
                  , nvl(os.definition, ot.definition) as description
                  , s.study_id
                  , s.stable_id as study_stable_id
                  , os.plural as display_name_plural
from (
select distinct s.study_id, iot.source_id as parent_stable_id, it.ENTITY_TYPE_ID as parent_id, ot.entity_type_id out_entity_type_id
from $SCHEMA.processattributes p
   , $SCHEMA.entityattributes i
   , $SCHEMA.entityattributes o
   , $SCHEMA.entitytype it
   , $SCHEMA.study s
   , $SCHEMA.entitytype ot
   , sres.ontologyterm iot
where s.study_id = $studyId 
and it.STUDY_ID = s.study_id
and ot.STUDY_ID = s.study_id
and it.ENTITY_TYPE_ID = i.entity_type_id
and ot.entity_type_id = o.entity_type_id
and p.in_entity_id = i.ENTITY_ATTRIBUTES_ID
and p.OUT_ENTITY_ID = o.ENTITY_ATTRIBUTES_ID 
and it.type_id = iot.ontology_term_id (+)
) et, $SCHEMA.entitytype t
   , $SCHEMA.study s
   , sres.ontologyterm ot
   , (select * from sres.ontologysynonym where external_database_release_id = $extDbRlsId) os
where s.study_id = $studyId 
 and s.study_id = t.study_id
 and t.study_id = et.study_id (+)
 and t.entity_type_id = out_entity_type_id (+)
 and t.type_id = ot.ontology_term_id (+)
 and ot.ontology_term_id = os.ontology_term_id (+)
";


  my $sh = $dbh->prepare($sql);
  $sh->execute();
  my $ct;

  while(my $row= $sh->fetchrow_hashref()) {
    $row->{'study_id'} = $studyId;

    my $etg = $self->getGusModelClass('EntityTypeGraph')->new($row);

    $etg->submit();
    $ct++
  }

  return $ct;
}


1;
