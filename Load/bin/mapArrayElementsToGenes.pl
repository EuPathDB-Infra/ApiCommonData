#!/usr/bin/perl

use strict;
use Getopt::Long;
use IO::File;
use DBI;
use CBIL::Util::PropertySet;



#----Usage/Example----
# perl    mapArrayElementsToGenes.pl    --aefExtDbSpec     --geneExtDbSpec     --aefSense "sense"
#---------------------


#my $startTime = time();
#print ("Started. Time: $startTime\n");

#------- Uid , Password and DSN ..these are fetched from the gus.config file----------

my ($gusConfigFile);
$gusConfigFile = $ENV{GUS_HOME} . "/config/gus.config" unless($gusConfigFile);

unless(-e $gusConfigFile) {
  print STDERR "gus.config file not found! \n";
  exit;
}


my @properties = ();
my $gusconfig = CBIL::Util::PropertySet->new($gusConfigFile, \@properties, 1);

my $u = $gusconfig->{props}->{databaseLogin};
my $pw = $gusconfig->{props}->{databasePassword};
my $dsn = $gusconfig->{props}->{dbiDsn};
my $dbh = DBI->connect($dsn, $u, $pw) or die DBI::errstr;
#----------------------------------------------------------------------


my ($geneExtDbSpec,$aefExtDbSpec,$aefSense,$outputFile);

&GetOptions('aefExtDbSpec=s' => \$aefExtDbSpec,
            'geneExtDbSpec=s' => \$geneExtDbSpec,
            'aefSense=s' =>\$aefSense,
            'outputFile=s' =>\$outputFile,
           );

die "ERROR: Please provide a valid External Database Spec ('name|version') for the Array Element Features"  unless ($aefExtDbSpec);
die "ERROR: Please provide a valid External Database Spec ('name|version') for Gene Features" unless ($geneExtDbSpec);
die "ERROR: Please provide a valid sense/direction ('sense','anitsense' or 'either') for the Array Element Features" unless (lc($aefSense) eq 'sense' || lc($aefSense) eq 'antisense' || lc($aefSense) eq 'either' );


my $geneExtDbRlsId = getDbRlsId($geneExtDbSpec);
my $aefExtDbRlsId = getDbRlsId($aefExtDbSpec);
print STDERR "Extracting Array Element Features.....\n";

my $aefSql = "select aef.na_sequence_id,
                     aef.source_id,
                     aef.name,
                     nl.start_min,
                     nl.end_max,
                     nl.is_reversed 
              from   dots.arrayelementfeature aef, 
                     dots.nalocation nl 
              where  aef.na_feature_id = nl.na_feature_id 
              and     aef.external_database_release_id = $aefExtDbRlsId";

my $sth = $dbh->prepare($aefSql);

$sth->execute || die "Could not execute SQL statement!";

my (%startAefHash,%endAefHash,%senseHash,%nameHash);

while( my ($aefSeqId,$aefSourceId,$aefName,$aefStartMin,$aefEndMax,$reversed) = $sth->fetchrow_array() ){
       $startAefHash{$aefSeqId}{$aefSourceId} = $aefStartMin;
       $endAefHash{$aefSeqId}{$aefSourceId} =  $aefEndMax;
       $senseHash{$aefSourceId} = $reversed;
       $nameHash{$aefSourceId} = $aefName; 
} 

print STDERR "Done extracting Array Element Features.\n";



print STDERR "Extracting Exon Features.....\n";
 
my $exonSql = "select ef.na_sequence_id,
                      ef.parent_id,
                      ef.source_id,
                      ef.coding_start,
                      ef.coding_end 
               from   dots.exonfeature ef 
               where  ef.external_database_release_id = $geneExtDbRlsId";

my $sth = $dbh->prepare($exonSql);

$sth->execute || die "Could not execute SQL statement!";

my (%startExonHash,%endExonHash,%geneExonHash);

while( my ($exonSeqId,$exonParentId,$exonSourceId,$exonStart,$exonEnd) = $sth->fetchrow_array() ){
    $startExonHash{$exonSeqId}{$exonSourceId} = $exonStart;
    $endExonHash{$exonSeqId}{$exonSourceId} = $exonEnd; 
    push @{ $geneExonHash{$exonParentId} },$exonSourceId;
}

print STDERR "Done extracting Exon Features.\n";



my $geneSql = "select ga.source_id, 
                      ga.na_sequence_id,
                      ga.is_reversed,
                      ga.na_feature_id 
               from   apidb.geneattributes ga,
                      sres.externaldatabase ed,
                      sres.externaldatabaserelease edr 
               where  ga.external_db_name = ed.name 
               and    ed.external_database_id = edr.external_database_id 
               and    edr.external_database_release_id = $geneExtDbRlsId";
#quicktest     and    ga.source_id = 'PF13_0333'";

my $sth = $dbh->prepare($geneSql);

$sth->execute || die "Could not execute SQL statement!";

print STDERR "Mapping Array Element Feature to Genes.....\n";

open (mapFile, ">$outputFile");

while( my ($geneSourceId,$geneSeqId,$geneReverse,$geneFeatureId) = $sth->fetchrow_array() ){
        
    my ($aefFeatureCount,@aefList,$exon,$aef);

    foreach $exon ( @{$geneExonHash{$geneFeatureId} }) {
        foreach $aef ( keys %{ $startAefHash{$geneSeqId} } ) {
            if ($geneReverse) {
                next if ( ($aefSense eq 'sense' && $senseHash{$aef} == 0) || ($aefSense eq 'antisense' && $senseHash{$aef} == 1) );
                if  ($startAefHash{$geneSeqId}{$aef} < $startExonHash{$geneSeqId}{$exon} && $endAefHash{$geneSeqId}{$aef} > $endExonHash{$geneSeqId}{$exon}) {
                    $aefFeatureCount = $aefFeatureCount + 1;
                    push @aefList, $nameHash{$aef};
                } 
            } else {
                next if ( ($aefSense eq 'sense' && $senseHash{$aef} == 1) || ($aefSense eq 'antisense' && $senseHash{$aef} == 0) );
                if  ($startAefHash{$geneSeqId}{$aef} < $endExonHash{$geneSeqId}{$exon} && $endAefHash{$geneSeqId}{$aef} > $startExonHash{$geneSeqId}{$exon}) {
                    $aefFeatureCount = $aefFeatureCount + 1;
                    push @aefList, $nameHash{$aef};
                } 
            }
        }
    }
    print (mapFile "$geneSourceId\t".join ("\t",@aefList)."\n") unless (scalar @aefList <1);
}

sub getDbRlsId {

  my ($extDbRlsSpec) = @_;

  my ($extDbName, $extDbRlsVer) = &getExtDbInfo($extDbRlsSpec);

  my $stmt = $dbh->prepare("select dbr.external_database_release_id from sres.externaldatabaserelease dbr,sres.externaldatabase db where db.name = ? and db.external_database_id = dbr.external_database_id and dbr.version = ?");

  $stmt->execute($extDbName,$extDbRlsVer);

  my ($extDbRlsId) = $stmt->fetchrow_array();

  return $extDbRlsId;
}

sub getExtDbInfo {
  my ($extDbRlsSpec) = @_;
  if ($extDbRlsSpec =~ /(.+)\|(.+)/) {
    my $extDbName = $1;
    my $extDbRlsVer = $2;
    return ($extDbName, $extDbRlsVer);
  } else {
    die("Database specifier '$extDbRlsSpec' is not in 'name|version' format");
  }
}
#my $endTime = time();
#print("Done. Time: $endTime\n");
