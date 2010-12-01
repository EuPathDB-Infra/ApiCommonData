package ApiCommonData::Load::Plugin::InsertGeneFeatProductFromTabFile;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;

use GUS::PluginMgr::Plugin;


use GUS::Model::DoTS::GeneFeature;
use GUS::Model::ApiDB::GeneFeatureProduct;
use GUS::Model::SRes::ExternalDatabase;
use GUS::Model::SRes::ExternalDatabaseRelease;
use ApiCommonData::Load::Util;

# ----------------------------------------------------------
# Load Arguments
# ----------------------------------------------------------

sub getArgsDeclaration {
  my $argsDeclaration  =
    [
     fileArg({ name => 'file',
	       descr => 'tab delimited file containing gene identifiers and product names',
	       constraintFunc=> undef,
	       reqd  => 1,
	       isList => 0,
	       mustExist => 1,
	       format => 'Two column tab delimited file in the order identifier, product',
	     }),
     stringArg({ name => 'productDbName',
		 descr => 'externaldatabase name for product name source',
		 constraintFunc=> undef,
		 reqd  => 1,
		 isList => 0
	       }),
     stringArg({ name => 'productDbVer',
		 descr => 'externaldatabaserelease version used for product name source',
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

  my $description = <<DESCR;
Plugin to load product names
DESCR

  my $purpose = <<PURPOSE;
Plugin to load product names
PURPOSE

  my $purposeBrief = <<PURPOSEBRIEF;
Plugin to load product names
PURPOSEBRIEF

  my $notes = <<NOTES;
NOTES

  my $tablesAffected = <<AFFECT;
ApiDB.GeneFeatureProduct
AFFECT

  my $tablesDependedOn = <<TABD;
DoTS.GeneFeature,SRes.ExternalDatabase,SRes.ExternalDatabaseRelease
TABD

  my $howToRestart = <<RESTART;
No restart provided. Must undo and reload.
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

  return ($documentation);

}


sub new {
  my $class = shift;
  my $self = {};
  bless($self, $class);

  my $documentation = &getDocumentation();

  my $args = &getArgsDeclaration();

  my $configuration = { requiredDbVersion => 3.5,
			cvsRevision => '$Revision$',
			name => ref($self),
			argsDeclaration => $args,
			documentation => $documentation
		      };

  $self->initialize($configuration);

  return $self;
}

sub run {
  my $self = shift;

  my $productReleaseId = $self->getExtDbRlsId($self->getArg('productDbName'),
						 $self->getArg('productDbVer')) || $self->error("Can't find external_database_release_id for product name source");

  my $tabFile = $self->getArg('file');

  my $processed;

  open(FILE,$tabFile) || $self->error("$tabFile can't be opened for reading");

  while(<FILE>){
      next if (/^\s*$/);

      my ($sourceId, $product) = split(/\t/,$_);

      my $preferred = 0;
	       
      my $geneFeature = GUS::Model::DoTS::GeneFeature->new({source_id => $sourceId, external_database_release_id => $productReleaseId});
      

      if($geneFeature->retrieveFromDB()){
	  my $geneFeatProduct = $geneFeature->getChild('ApiDB::GeneFeatureProduct',1);

	  $preferred = 1 unless $geneFeatProduct;

	  my $nafeatureId = $geneFeature->getNaFeatureId();
    
	  $self->makeGeneFeatProduct($productReleaseId,$nafeatureId,$product,$preferred);
  
	  $processed++;
      }else{
	  $self->log("WARNING","Gene Feature with source id: $sourceId and external database release id $productReleaseId cannot be found");
      }
      
      $self->undefPointerCache();
  }        




  return "$processed gene feature products parsed and loaded";
}


sub makeGeneFeatProduct {
  my ($self,$productReleaseId,$naFeatId,$product,$preferred) = @_;

  my $geneFeatProduct = GUS::Model::ApiDB::GeneFeatureProduct->new({'na_feature_id' => $naFeatId,
						                    'product' => $product,
						                     });

  unless ($geneFeatProduct->retrieveFromDB()){
      $geneFeatProduct->set("is_preferred",$preferred);
      $geneFeatProduct->set("external_database_release_id",$productReleaseId);
      $geneFeatProduct->submit();
  }else{
      $self->log("WARNING","product $product already exists for na_feature_id: $naFeatId");
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
  return ('ApiDB.GeneFeatureProduct',
	  'SRes.ExternalDatabaseRelease',
	  'SRes.ExternalDatabase',
	 );
}

