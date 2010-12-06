package ApiCommonData::Load::Plugin::InsertGeneNamesFromTabFile;

@ISA = qw(GUS::PluginMgr::Plugin);

#######################################
#    InsertGeneNamesFromTabFile.pm
#  
#   Plugin to load GeneName numbers from a
#   variety of tab delimited files. 
#  
#
# Vishal Nayak, Nov, 2010
#######################################

use strict;

use DBI;
use CBIL::Util::Disp;
use GUS::PluginMgr::Plugin;
use ApiCommonData::Load::Util;
use GUS::Model::DoTS::GeneFeature;
use GUS::Model::ApiDB::GeneFeatureName;
use GUS::Model::SRes::ExternalDatabase;
use GUS::Model::SRes::ExternalDatabaseRelease;
use Data::Dumper;

# ----------------------------------------------------------
# Load Arguments
# ----------------------------------------------------------

sub getArgsDeclaration {
my $argsDeclaration  =
[
stringArg({name => 'file',
         descr => 'path and filename for the data file',
         constraintFunc=> undef,
         reqd  => 1,
         isList => 0,
	 mustExist => 1,
	 format => 'Two column tab delimited file in the order identifier, gene_name',
        }),
stringArg({ name => 'geneNameDbName',
		 descr => 'externaldatabase name for gene name source',
		 constraintFunc=> undef,
		 reqd  => 1,
		 isList => 0
	 }),
stringArg({ name => 'geneNameDbVer',
	  descr => 'externaldatabaserelease version used for gene name source',
	  constraintFunc=> undef,
	  reqd  => 1,
	  isList => 0
	 })

];

return $argsDeclaration;
}


# ----------------------------------------------------------
# Documentation
# ----------------------------------------------------------

sub getDocumentation {

my $description = <<NOTES;
Application to load gene names from tab-delimited files.  The files contain the source_id and the gene name. 
NOTES

my $purpose = <<PURPOSE;
Load Gene Names from tab-delimited files.
PURPOSE

my $purposeBrief = <<PURPOSEBRIEF;
Load Gene Names.
PURPOSEBRIEF

my $syntax = <<SYNTAX;
SYNTAX

my $notes = <<NOTES;
NOTES

my $tablesAffected = <<AFFECT;
ApiDB.GeneName
AFFECT

my $tablesDependedOn = <<TABD;
DoTS.Gene
TABD

my $howToRestart = <<RESTART;
The submit does a retrieveFromDb test for the new value to avoid duplicates, so you can restart simply by restatring in the middle of a run.
RESTART

my $failureCases = <<FAIL;
FAIL

my $documentation = {purpose=>$purpose, purposeBrief=>$purposeBrief,tablesAffected=>$tablesAffected,tablesDependedOn=>$tablesDependedOn,howToRestart=>$howToRestart,failureCases=>$failureCases,notes=>$notes};

return ($documentation);

}


#*****************************************************
#Let there be objects!
#*****************************************************
sub new {
   my $class = shift;
   my $self = {};
   bless($self, $class);
                                                                                                                             
      my $documentation = &getDocumentation();
                                                                                                                             
      my $args = &getArgsDeclaration();
                                                                                                                             
      $self->initialize({requiredDbVersion => 3.5,
                     cvsRevision => '$Revision: 30461 $',
                     name => ref($self),
                     argsDeclaration   => $args,
                     documentation     => $documentation
                    });
   return $self;
}


###############################################################
#Main Routine
##############################################################

sub run{
  my $self = shift;

  my $geneNameReleaseId = $self->getOrCreateExtDbAndDbRls($self->getArg('geneNameDbName'),
						 $self->getArg('geneNameDbVer')) || $self->error("Can't find or create external_database_release_id for gene name source");
  my $tabFile = $self->getArg('file');

  my $processed;

  open(FILE,$tabFile) || $self->error("$tabFile can't be opened for reading");

  while(<FILE>){
      next if (/^\s*$/);

      my ($sourceId, $geneName) = split(/\t/,$_);

      my $preferred = 0;

      my $geneFeature = GUS::Model::DoTS::GeneFeature->new({source_id => $sourceId, external_database_release_id => $geneNameReleaseId});

 	       
      if($geneFeature->retrieveFromDB()){
	  my $geneNameFeat = $geneFeature->getChild('ApiDB::GeneFeatureName',1);

	  $preferred = 1 unless $geneNameFeat;

	  my $nafeatureId = $geneFeature->getNaFeatureId();	       
    
	  $self->makeGeneName($geneNameReleaseId,$nafeatureId,$geneName,$preferred);
  
	  $processed++;
      }else{
	  $self->log("WARNING","Gene Feature with source id: $sourceId cannot be found");
      }  
      $self->undefPointerCache();
  }        




  return "$processed gene names parsed and loaded";	  
  
}

sub makeGeneName {
  my ($self,$geneNameReleaseId,$nafeatureId,$geneName,$preferred) = @_;

  my $geneNameFeat = GUS::Model::ApiDB::GeneFeatureName->new({'na_feature_id' => $nafeatureId,
						     'name' => $geneName,
						     });


  unless ($geneNameFeat->retrieveFromDB()){
      $geneNameFeat->set("is_preferred",$preferred);
      $geneNameFeat->set("external_database_release_id",$geneNameReleaseId);
      $geneNameFeat->submit();
  }else{
      $self->log("WARNING","Gene Name $geneName already exists for na_feature_id: $nafeatureId");
  }

}


sub getOrCreateExtDbAndDbRls{
  my ($self, $dbName,$dbVer) = @_;

  my $extDbId=$self->InsertExternalDatabase($dbName);

  my $extDbRlsId=$self->InsertExternalDatabaseRls($dbName,$dbVer,$extDbId);

  return $extDbRlsId;
}

sub InsertExternalDatabase{

    my ($self,$dbName) = @_;
    my $extDbId;

    my $sql = "select external_database_id from sres.externaldatabase where lower(name) like '" . lc($dbName) ."'";
    my $sth = $self->prepareAndExecute($sql);
    $extDbId = $sth->fetchrow_array();

    if ($extDbId){
	print STEDRR "Not creating a new entry for $dbName as one already exists in the database (id $extDbId)\n";
    }

    else {
	my $newDatabase = GUS::Model::SRes::ExternalDatabase->new({
	    name => $dbName,
	   });
	$newDatabase->submit();
	$extDbId = $newDatabase->getId();
	print STEDRR "created new entry for database $dbName with primary key $extDbId\n";
    }
    return $extDbId;
}

sub InsertExternalDatabaseRls{

    my ($self,$dbName,$dbVer,$extDbId) = @_;

    my $extDbRlsId = $self->releaseAlreadyExists($extDbId,$dbVer);

    if ($extDbRlsId){
	print STDERR "Not creating a new release Id for $dbName as there is already one for $dbName version $dbVer\n";
    }

    else{
        $extDbRlsId = $self->makeNewReleaseId($extDbId,$dbVer);
	print STDERR "Created new release id for $dbName with version $dbVer and release id $extDbRlsId\n";
    }
    return $extDbRlsId;
}


sub releaseAlreadyExists{
    my ($self, $extDbId,$dbVer) = @_;

    my $sql = "select external_database_release_id 
               from SRes.ExternalDatabaseRelease
               where external_database_id = $extDbId
               and version = '$dbVer'";

    my $sth = $self->prepareAndExecute($sql);
    my ($relId) = $sth->fetchrow_array();

    return $relId; #if exists, entry has already been made for this version

}

sub makeNewReleaseId{
    my ($self, $extDbId,$dbVer) = @_;

    my $newRelease = GUS::Model::SRes::ExternalDatabaseRelease->new({
	external_database_id => $extDbId,
	version => $dbVer,
	download_url => '',
	id_type => '',
	id_url => '',
	secondary_id_type => '',
	secondary_id_url => '',
	description => '',
	file_name => '',
	file_md5 => '',
	
    });

    $newRelease->submit();
    my $newReleasePk = $newRelease->getId();

    return $newReleasePk;

}

sub undoTables {
  return ('ApiDB.GeneFeatureName',
	  'SRes.ExternalDatabaseRelease',
	  'SRes.ExternalDatabase',
	 ); 
}

return 1;

