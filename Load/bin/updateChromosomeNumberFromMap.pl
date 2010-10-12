#!/usr/bin/perl

use strict;
use lib "$ENV{GUS_HOME}/lib/perl";

use CBIL::Util::PropertySet;
use Getopt::Long;
use DBI;
use DBD::Oracle;

my ($help, $fn, $gusConfigFile, $sequenceTable);

&GetOptions('help|h' => \$help,
            'map_file=s' => \$fn,
            'gus_config_file=s' => \$gusConfigFile,
            'sequence_table=s' => \$sequenceTable,
            );

#============================================

$gusConfigFile = $ENV{GUS_HOME} . "/config/gus.config" unless($gusConfigFile);

unless(-e $fn && -e $fn && $sequenceTable) {
  print STDERR "usage --map_file map_file --sequence_table 'ExternalNaSequence|VirtualSequence' [--gus_config_file]\n";
  exit;
}

my @properties = ();
my $gusconfig = CBIL::Util::PropertySet->new($gusConfigFile, \@properties, 1);

my $u = $gusconfig->{props}->{databaseLogin};
my $pw = $gusconfig->{props}->{databasePassword};
my $dsn = $gusconfig->{props}->{dbiDsn};

my $dbh = DBI->connect($dsn, $u, $pw) or die DBI::errstr;
$dbh->{RaiseError} = 1;
$dbh->{AutoCommit} = 0;

open(FILE, $fn) or die "Cannot open file $fn for reading:$!";

my $sql = "update dots.$sequenceTable set chromosome = ?, chromosome_order_num = ?, modification_date=sysdate where source_id = ?";
my $sh = $dbh->prepare($sql);

my $error;

while(<FILE>) {
  chomp;
  my ($sourceId, $chr_order_num, $chrom) = split(/\t/, $_);

  next unless($chr_order_num);

  $chrom = "chromosome $chr_order_num" unless $chrom;

  $sh->execute($chrom, $chrom, $sourceId);
  my $rowCount = $sh->rows;
  unless($rowCount == 1) {
    print STDERR "ERROR:  Chrom $sourceId updated $rowCount rows !!!\n";
    $error = 1;
  }
}

if($error) {
  $dbh->rollback();
  print STDERR "Errors!  Rolled back database\n";
}

$dbh->commit;
print STDERR "Update Complete\n";

close FILE;

1;
