#$Id$
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
  # GUS4_STATUS | dots.gene                      | manual | fixed
#^^^^^^^^^^^^^^^^^^^^^^^^^ End GUS4_STATUS ^^^^^^^^^^^^^^^^^^^^
#TODO: Test restart method
package ApiCommonData::Load::Plugin::InsertSingleMotifMultMappings;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;

use FileHandle;
use GUS::Model::DoTS::PredictedAAFeature;
use GUS::Model::DoTS::AALocation;
use GUS::Model::DoTS::MotifAASequence;
use GUS::PluginMgr::Plugin;
use GUS::Supported::Util;

my $purposeBrief = <<PURPOSEBRIEF;
Inserts motif data from a 2-column tab delimited file containing the sequence ID and the start location of the motif.
PURPOSEBRIEF

my $purpose = <<PLUGIN_PURPOSE;
Takes a motif and a 2-column tab delimited file containing the source ids of multiple proteins that contain the motif and the start site of the motif within the sequence.  This data is entered into the predictedAAFeature and AALocation tables to provide a mapping of the motif on the proteins.
PLUGIN_PURPOSE

my $tablesAffected = [['DoTS::PredictedAAFeature','The links to the AA sequence and the motif are made here.'],['DoTS::AALocation','The start and end location of the motif on the given sequence is located here.'],['DoTS::MotifAASequence','The motif is stored here.']];

my $tablesDependedOn = ['DoTS::TranslatedAASequence','The sequence that the motif is found in must be in this table.'];

my $howToRestart = <<PLUGIN_RESTART;
Provide the restart flag with the algInvocation number of the run that failed.
PLUGIN_RESTART

my $failureCases = <<PLUGIN_FAILURE_CASES;
unknown
PLUGIN_FAILURE_CASES

my $notes = <<PLUGIN_NOTES;
This plugin takes a two column tab delimited file of the form: source_id   start location
PLUGIN_NOTES

my $documentation = {purposeBrief => $purposeBrief,
		     purpose => $purpose,
		     tablesAffected => $tablesAffected,
		     tablesDependedOn => $tablesDependedOn,
		     howToRestart => $howToRestart,
		     failureCases => $failureCases,
		     notes => $notes
		    };


my $argsDeclaration =
[

 fileArg({name => 'inputFile',
	  descr => 'name of the file to load',
	  constraintFunc => undef,
	  reqd => 1,
	  isList => 0,
	  mustExist => 1,
	  format => 'tab delimited: source_id   startLocation'
        }),

 stringArg({name => 'motif',
	    descr => 'the regex for the motif that is found in the sequences',
	    constraintFunc => undef,
	    reqd => 1,
	    isList => 0
	   }),

 stringArg({name => 'motifName',
	    descr => 'the name for the motif',
	    constraintFunc => undef,
	    reqd => 0,
	    isList => 0
	   }),

 stringArg({name => 'description',
	    descr => 'a short description of the motif',
	    constraintFunc => undef,
	    reqd => 0,
	    isList => 0
	   }),

 stringArg({name => 'category',
	    descr => 'category into which the sequences containing the motif fall, ex: secretome, proteome, etc.',
	    constraintFunc => undef,
	    reqd => 0,
	    isList => 0
	   }),

 stringArg({name => 'extDbRelSpec',
	    descr => 'The external database specifications for the motif data in the form "name|version"',
	    constraintFunc => undef,
	    reqd => 1,
	    isList => 0
	   }),

 stringArg({name => 'seqExtDbRelSpec',
	    descr => 'The external database specifications for the aa sequences in which the motif is found, in the form "name|version"',
	    constraintFunc => undef,
	    reqd => 1,
	    isList => 0
	   }),

   stringArg({name => 'organismAbbrev',
	      descr => 'if supplied, use a prefix to use for tuning manager tables',
	      reqd => 0,
	      constraintFunc => undef,
	      isList => 0,
	     }),

 stringArg({name => 'restart',
	    descr => 'a list of algInvocation numbers for runs that failed',
	    constraintFunc => undef,
	    reqd => 0,
	    isList => 1
	   }),


 ];

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);

    $self->initialize({requiredDbVersion => 4.0,
		       cvsRevision =>  '$Revision$',
		       name => ref($self),
		       argsDeclaration   => $argsDeclaration,
		       documentation     => $documentation
		      });

    return $self;
}


sub run{
  my($self) = @_;
  my $added = 0;
  my $skipped = 0;
  my %done;

  my $motif = $self->getArg('motif');
  my $length = length($motif);

  my $extDbRls = $self->getExtDbRlsId($self->getArg('extDbRelSpec'))
      || die "Couldn't retrieve external database!\n";

  my $seqExtDbRls = $self->getExtDbRlsId($self->getArg('seqExtDbRelSpec'))
      || die "Couldn't retrieve the sequence external database!\n";


  my $motifId = $self->insertMotif($extDbRls, $motif, $length);


  my $restart = $self->getArg('restart');

  if($restart){
    my $restartIds = join(",",@$restart);
    %done = $self->restart($restartIds);
    $self->log("Restarting with algorithm invocation IDs: $restartIds");
  }

  my $file = $self->getArg('inputFile');
  open (FILE, "<$file") or $self->error("Couldn't open file '$file': $!\n");

  while(<FILE>){
    chomp;

    my ($sourceId, $start) = split(/\t/, $_);

    unless(%done->{$sourceId}){

	my $aaSeqIds;

	if ($self->getArg('organismAbbrev')){

	      $aaSeqIds = &GUS::Supported::Util::getAASeqIdsFromGeneId($self,$sourceId,$seqExtDbRls,$self->getArg('organismAbbrev'));
	}else{
	      $aaSeqIds = &GUS::Supported::Util::getAASeqIdsFromGeneId($self,$sourceId,$seqExtDbRls);
        }

      foreach my $aaSeqId(@$aaSeqIds){

	my $newPredAAFeat = $self->createPredictedAAFeature($extDbRls, $sourceId, $aaSeqId, $motifId);

	my $newAALoc = $self->createAALocation($start, $length);

	$$newPredAAFeat->addChild($$newAALoc);
	$$newPredAAFeat->submit();
	$added++;

      }

       if(scalar @$aaSeqIds ==0) {
         $skipped++;
         $self->undefPointerCache();
         next;
       }
    }
    $self->undefPointerCache();
  }

  my $msg = "Added $added new features.  Skipped $skipped features because source ID was not found.";
  return $msg;
}

sub createPredictedAAFeature{
  my ($self, $extDbRls, $sourceId, $aaSeqId, $motifId) = @_;

  my $category = $self->getArg('category');

  my $aaFeature = GUS::Model::DoTS::PredictedAAFeature->new({external_database_release_id => $extDbRls,
							     aa_sequence_id => $aaSeqId,
							     motif_aa_sequence_id => $motifId,
							     source_id => $sourceId,
							     name=> $category,
							     is_predicted => 1,
							     subclass_view => "PredictedAAFeature",
							    });

  return \$aaFeature;
}

sub createAALocation{
  my ($self, $start, $length) = @_;

  my $end = $start + $length;

  my $aaLocation = GUS::Model::DoTS::AALocation->new({start_min => $start,
						      start_max => $start,
						      end_min => $end,
						      end_max => $end,
						     });

  return \$aaLocation;

}


sub insertMotif{
  my ($self, $extDbRls, $motif, $length) = @_;
  my $desc = $self->getArg('description');
  my $motifName = $self->getArg('motifName');

  my $aaMotif = GUS::Model::DoTS::MotifAASequence->new({external_database_release_id => $extDbRls,
							length => $length,
							description => $desc,
							name => $motifName,
							subclass_view => "MotifAASequence",
						       });

  unless($aaMotif->retrieveFromDB()){
    $aaMotif->setSequence($motif);
    $self->log("Inserting motif '$motif'.");
    $aaMotif->submit();
  }

  my $motifId = $aaMotif->getId();

  return $motifId;
}


sub restart{
  my ($self, $restartIds) = @_;
  my %done;

  my $sql = "SELECT source_id FROM DoTS.PredictedAAFeature WHERE row_alg_invocation_id IN ($restartIds)";

  my $qh = $self->getQueryHandle();
  my $sth = $qh->prepareAndExecute($sql);

    while(my ($id) = $sth->fetchrow_array()){
	$done{$id}=1;
    }
    $sth->finish();

  return %done;
}

# ----------------------------------------------------------------------

sub undoTables {
  my ($self) = @_;

  return ('DoTS.AALocation',
	  'DoTS.PredictedAAFeature',
	  'DoTS.MotifAASequence',
	 );
}

1;
