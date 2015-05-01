package ApiCommonData::Load::KEGGMetabolicPathway;
use base qw(ApiCommonData::Load::MetabolicPathway);

use strict;
use Data::Dumper;

use GUS::Model::SRes::Pathway;
use GUS::Model::SRes::PathwayNode;
use GUS::Model::SRes::PathwayRelationship;

use GUS::Model::ApiDB::PathwayReaction;
use GUS::Model::ApiDB::PathwayReactionRel;

sub getReaderClass {
  return "GUS::Supported::KEGGReader";
}

sub makeGusObjects {
  my ($self) = @_;


  my $reader = $self->getReader();
  my $pathwayHash = $reader->getPathwayHash();

  my $typeToTableMap = {compound => 'ApiDB::PubChemCompound', enzyme => 'SRes::EnzymeClass', map => 'SRes::Pathway' };
  my $typeToOntologyTerm = {compound => 'molecular entity', map => 'metabolic process', enzyme => 'enzyme'};

  print STDERR "Making GUS Objects for pathway $pathwayHash->{NAME} ($pathwayHash->{SOURCE_ID} )\n";

  my $pathway = GUS::Model::SRes::Pathway->new({name => $pathwayHash->{NAME}, 
                                               source_id => $pathwayHash->{SOURCE_ID},
                                                external_database_release_id => $self->getExtDbRlsId(),
                                               url => $pathwayHash->{URI}
                                               });


  $self->setPathway($pathway);

  # MAKE NODES
  foreach my $node (values %{$pathwayHash->{NODES}}) {
    my $keggType = $node->{TYPE};
    my $keggSourceId = $node->{SOURCE_ID};

    my $type = $typeToOntologyTerm->{$keggType};
    my $tableName = $typeToTableMap->{$keggType};

    next unless($type); 

    my $typeId = $self->mapAndCheck($type, $self->getOntologyTerms());
    my $tableId = $self->mapAndCheck($tableName, $self->getTableIds());
    my $rowId = $self->getRowIds()->{$tableName}->{$keggSourceId};

    unless($rowId) {
      print STDERR "WARN:  Could not find Identifier for $keggSourceId\n";
      $tableId = undef;
    }

    my $gusNode = GUS::Model::SRes::PathwayNode->new({'display_label' => $keggSourceId,
                                                   'pathway_node_type_id' => $typeId,
                                                   'x' => $node->{GRAPHICS}->{X},
                                                   'y' => $node->{GRAPHICS}->{Y},
                                                   'height' => $node->{GRAPHICS}->{HEIGHT},
                                                   'width' => $node->{GRAPHICS}->{WIDTH},
                                                   'table_id' => $tableId,
                                                   'row_id' => $rowId,
                                                  });

    $gusNode->setParent($pathway);

    my $uniqueNodeId = $node->{ENTRY_ID};
    $self->addNode($gusNode, $uniqueNodeId);
  }

  # MAKE REACTIONS AND RELATIONS
  my $relationshipTypeId = $self->getOntologyTerms()->{'metabolic process'};

  foreach my $reaction (values %{$pathwayHash->{REACTIONS}}) {
    my $reactionSourceId = $reaction->{SOURCE_ID};
    my $gusReaction = GUS::Model::ApiDB::PathwayReaction->new({source_id => $reactionSourceId});
    $self->addReaction($gusReaction, $reactionSourceId);
  }

  foreach my $compoundId (keys %{$pathwayHash->{EDGES}}) {
    my $compoundNode = $pathwayHash->{NODES}->{$compoundId};
    my $compoundSourceId = $compoundNode->{SOURCE_ID};
    my $gusCompoundNode = $self->getNodeByUniqueId($compoundId);

    foreach my $otherId (@{$pathwayHash->{EDGES}->{$compoundId}}) {
      my $otherNode = $pathwayHash->{NODES}->{$otherId};
      my $gusOtherNode = $self->getNodeByUniqueId($otherId);

      my $gusRelationship = GUS::Model::SRes::PathwayRelationship->new({relationship_type_id => $relationshipTypeId});;
      if($otherNode->{TYPE} eq 'enzyme') {
        my $reactionId = $otherNode->{REACTION};
        $reactionId =~ s/rn\://g;
        my $reactionHash = $self->findReactionById($reactionId);


        if($reactionHash) {
          my $gusReaction = $self->getReactionByUniqueId($reactionId);

          my $isReversible;
          if($reactionHash->{TYPE} eq 'irreversible') {
            $isReversible = 0;
          }
          if($reactionHash->{TYPE} eq 'reversible') {
            $isReversible = 1;
          }

          if(&existsInArrayOfHashes($compoundSourceId, $reactionHash->{SUBSTRATES})) {
            $gusRelationship->setParent($gusCompoundNode, "node_id");
            $gusRelationship->setParent($gusOtherNode, "associated_node_id");
            $gusRelationship->setIsReversible($isReversible);
          }
          elsif(&existsInArrayOfHashes($compoundSourceId, $reactionHash->{PRODUCTS})) {
            $gusRelationship->setParent($gusOtherNode, "node_id");
            $gusRelationship->setParent($gusCompoundNode, "associated_node_id");
            $gusRelationship->setIsReversible($isReversible);
          }
          else {
            die "Could not find compound $compoundId in either substrates or products ";
          }


          my $pathwayReactionRel = GUS::Model::ApiDB::PathwayReactionRel->new();
          $pathwayReactionRel->setParent($gusReaction);
          $pathwayReactionRel->setParent($gusRelationship);
        }
        else {
          print STDERR "WARN:  Reaction $reactionId not found in this map xml file... cannot set is_reversible for this relation\n";
          $gusRelationship->setParent($gusCompoundNode, "node_id");
          $gusRelationship->setParent($gusOtherNode, "associated_node_id");
        }
      }
      elsif($otherNode->{TYPE} eq 'map') {
          $gusRelationship->setParent($gusCompoundNode, "node_id");
          $gusRelationship->setParent($gusOtherNode, "associated_node_id");

          #TODO:  How would I ever know if this is reversible??
      }
      else {
        print  "WARN:  Edge should only be compound to X where X is either an enzyme or a map.  Found $otherNode->{TYPE}... skipping\n";
        next;
      }

      $self->addRelationship($gusRelationship);
    }
  }

}

sub existsInArrayOfHashes {
  my ($e, $ar) = @_;

  foreach(@$ar) {
    return 1 if($e == $_->{NAME});
  }

  return 0;
}



sub findReactionById {
  my ($self, $reactionId) = @_;

  my $reader = $self->getReader();
  my $pathwayHash = $reader->getPathwayHash();

  foreach my $reaction (values %{$pathwayHash->{REACTIONS}}) {
    return $reaction if($reaction->{SOURCE_ID} eq $reactionId);
  }

}


sub mapAndCheck {
  my ($self, $key, $hash) = @_;

  my $rv = $hash->{$key};

  unless($rv) {
    die "Could not determine value for term $key in hash";
  }

  return $rv;
}

1;

