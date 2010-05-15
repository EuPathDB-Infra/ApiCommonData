package ApiCommonData::Load::Plugin::InsertECsFromTabFile;
@ISA = qw(GUS::PluginMgr::Plugin);

#######################################
#    InsertECsFromTabFile.pm
#  
#   Plugin to load EC numbers from a
#   variety of tab delimited files. 
#  
#
# Ed Robinson, Feb, 2006 
#######################################

use strict;

use DBI;
use CBIL::Util::Disp;
use GUS::PluginMgr::Plugin;
use ApiCommonData::Load::Util;
use ApiCommonData::Load::Utility::ECAnnotater;
use Data::Dumper;

# ----------------------------------------------------------
# Load Arguments
# ----------------------------------------------------------

sub getArgsDeclaration {
my $argsDeclaration  =
[
stringArg({name => 'ecFile',
         descr => 'path and filename for the data file',
         constraintFunc=> undef,
         reqd  => 1,
         isList => 0,
        }),

stringArg({name => 'ECDbName',
         descr => 'name of the Enzyme database in SRes.ExternalDatabase',
         constraintFunc=> undef,
         reqd  => 1,
         isList => 0,
        }),

stringArg({name => 'ECReleaseNumber',
         descr => 'version of the Enzyme Database in SRes.ExternalDatabaseRelease',
         constraintFunc=> undef,
         reqd  => 1,
         isList => 0,
        }),

stringArg({name => 'evidenceCode',
         descr => 'String describing where the evidence for this association originated (e.g. Annotation Center)',
         constraintFunc=> undef,
         reqd  => 1,
         isList => 0,
        }),

stringArg({name => 'upperCase',
         descr => 'if gene name should be upper cased (ucFirst), upperCase=1',
         constraintFunc=> undef,
         reqd  => 0,
         isList => 0,
        }),
];

return $argsDeclaration;
}


# ----------------------------------------------------------
# Documentation
# ----------------------------------------------------------

sub getDocumentation {

my $description = <<NOTES;
Application to load ECs from tab delimited files produced by Kegg and CryptoCyc.  The files contain the source_id and the raw ec number.  They also require some cleaning before hand.  This plugin will be folded into ApiCommonData::Load::Plugin::InsertECMapping in the near future.
NOTES

my $purpose = <<PURPOSE;
Load EC numbers from Kegg and CryptoCyc data dumps.
PURPOSE

my $purposeBrief = <<PURPOSEBRIEF;
Load EC Numbers.
PURPOSEBRIEF

my $syntax = <<SYNTAX;
SYNTAX

my $notes = <<NOTES;
Uses the ECAnnotater module which required that you have a ExternalDatabaseId for the enzyme data base, and evidence description specifying where the annotation came from, and a sequence id and raw EC number.
NOTES

my $tablesAffected = <<AFFECT;
DoTS.AASequenceEnzymeClass
AFFECT

my $tablesDependedOn = <<TABD;
DoTS.TranslatedAASequence
DoTS.SRes.EnzymeClass
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
                     cvsRevision => '$Revision$',
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

  my $file = $self->getArg('ecFile');
  my $evidenceDescription = $self->getArg('evidenceCode');

  my $dbRls = $self->getExtDbRlsId($self->getArg('ECDbName'),
                                     $self->getArg('ECReleaseNumber'))
      || die "Couldn't retrieve external database!\n";

  $self->logAlgInvocationId;
  $self->logCommit;

  my $annotater = ApiCommonData::Load::Utility::ECAnnotater->new();

  open(ECFILE, $file)
    || die "can't open file $file";

    my $ecCount = 0;

    while (<ECFILE>) {
       chomp;
       my ($gene,$ec) = $self->parseRow($_);
       if ($gene & $ec) {
       my $aaSeq = ApiCommonData::Load::Util::getAASeqIdFromGeneId($self, $gene);
       my $ecAssociation = {
                    'ecNumber' => $ec,
                    'evidenceDescription' => $evidenceDescription,
                    'releaseId' => $dbRls,
                    'sequenceId' => $aaSeq,
                              };
       $annotater->addEnzymeClassAssociation($ecAssociation);
          $ecCount++;
       }
    }
$self->log("Processed $ecCount EC Numbers");
}


sub parseRow {
   my ($self, $line) = @_;

      #cho:Chro.10335  ec:4.1.2.13              Kegg data
      #CGD1_1170       3.4.19.12                Cyc Data
      my ($gene,$ec) = split(/\t/,$line);
      $gene =~ s/\w+\://; 
      $ec =~ s/\w+\://; 
      $gene =~ tr/[A-Z]/[a-z]/;
      if ($self->getArg('upperCase')) {
          $gene = ucfirst($gene);
       }

return ($gene, $ec);
}

sub undoTables {
    ApiCommonData::Load::Utility::ECAnnotater->undoTables();
}

return 1;

