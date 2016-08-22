#!/usr/bin/perl
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

use strict;

use lib "$ENV{GUS_HOME}/lib/perl";

use CBIL::Util::PropertySet;
use Getopt::Long;
use DBI;
use DBD::Oracle;

my ($verbose,$gusConfigFile);

&GetOptions("verbose!"=> \$verbose,
            'gus_config_file=s' => \$gusConfigFile,
            );

#============================================

$gusConfigFile = $ENV{GUS_HOME} . "/config/gus.config" unless($gusConfigFile);

my @properties = ();
my $gusconfig = CBIL::Util::PropertySet->new($gusConfigFile, \@properties, 1);

my $u = $gusconfig->{props}->{databaseLogin};
my $pw = $gusconfig->{props}->{databasePassword};
my $dsn = $gusconfig->{props}->{dbiDsn};

my $dbh = DBI->connect($dsn, $u, $pw) or die DBI::errstr;
$dbh->{RaiseError} = 1;
$dbh->{AutoCommit} = 0;

my $sqldbref = "select distinct r.db_ref_id
from dots.genefeature official, dots.dbrefnafeature df, dots.genefeature other, sres.dbref r 
where official.na_feature_id = df.na_feature_id 
and other.source_id = r.primary_identifier 
and df.db_ref_id = r.db_ref_id";

my $sqldbrefnafeaturedelete = "delete from dots.dbrefnafeature where db_ref_id= ?";
my $sqldbrefdelete = "delete from sres.dbref where db_ref_id = ?";

my $sqldateupdate1="update dots.dbrefnafeature set modification_date=sysdate";
my $sqldateupdate2="update sres.dbref set modification_date=sysdate";

my $select = $dbh->prepare($sqldbref);
my $delete1 = $dbh->prepare($sqldbrefnafeaturedelete);
my $delete2 = $dbh->prepare($sqldbrefdelete);
my $update1 = $dbh->prepare($sqldateupdate1);
my $update2 = $dbh->prepare($sqldateupdate2);

$select ->execute();

my $dbrefNaFeatureCount;
my $dbrefCount;
my $error;

my @dbRefIds;

while (my ($db_ref_id) = $select->fetchrow_array()){
  push @dbRefIds, $db_ref_id;
}

foreach(@dbRefIds) {

  #There may be many dbrefnafeature for a given db_ref_id
  $delete1 ->execute($_);
  $dbrefNaFeatureCount = $dbrefNaFeatureCount + $delete1->rows;

  $delete2 ->execute($_);
  my $delete2Rows = $delete2->rows;
  $dbrefCount = $dbrefCount + $delete2Rows;

  # using the primary key should only be able to delete one row
  unless($delete2Rows == 1) {
    print STDERR "ERROR:   db_ref_id [$_] deleted $delete2Rows rows from sres.dbref !!!\n";
    $error = 1;
  }
}

$update1->execute();
$update2->execute();

$select->finish();
$delete1->finish();
$delete2->finish();
$update1->finish();
$update2->finish();

if($error) {
  $dbh->rollback();
  print STDERR "Errors!  Rolled back database\n";
}
else {
  $dbh->commit;
  print "Deleted $dbrefNaFeatureCount from Dots.DbrefNaFeature and $dbrefCount from SRes.DbRef\n";
}

$dbh->disconnect();

1;
