package ApiCommonData::Load::Plugin::InsertAnalysisMethodInvocation;
@ISA = qw(GUS::PluginMgr::Plugin);
 
use strict;

use FileHandle;
use GUS::ObjRelP::DbiDatabase;
use GUS::Model::ApiDB::AnalysisMethodInvocation;
use GUS::PluginMgr::Plugin;

$| = 1;


my $argsDeclaration =
[

 stringArg({name => 'name',
	    descr => '',
	    constraintFunc => undef,
	    reqd => 1,
	    isList => 0
	   }),

 stringArg({name => 'version',
	    descr => '',
	    constraintFunc => undef,
	    reqd => 1,
	    isList => 0
	   }),

 stringArg({name => 'parameters',
	    descr => '',
	    constraintFunc => undef,
	    reqd => 1,
	    isList => 0
	   }),
 ];


my $purposeBrief = <<PURPOSEBRIEF;
Insert a record of an analysis method invocation.
PURPOSEBRIEF

my $purpose = <<PLUGIN_PURPOSE;
Insert a record of an analysis method invocation.
PLUGIN_PURPOSE

my $tablesAffected = [
['ApiDB.AnalysisMethodInvocation','One row is added to this table']
];

my $tablesDependedOn = [];

my $howToRestart = <<PLUGIN_RESTART;
This plugin cannot be restarted.
PLUGIN_RESTART

my $failureCases = <<PLUGIN_FAILURE_CASES;
unknown
PLUGIN_FAILURE_CASES

my $notes = <<PLUGIN_NOTES;
This plugin is typically called to document the methods used in a workflow step.It assumes that the pubmed_id has been resolved into a citation previously.
PLUGIN_NOTES

my $documentation = {purposeBrief => $purposeBrief,
		     purpose => $purpose,
		     tablesAffected => $tablesAffected,
		     tablesDependedOn => $tablesDependedOn,
		     howToRestart => $howToRestart,
		     failureCases => $failureCases,
		     notes => $notes
		    };


sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);

    $self->initialize({requiredDbVersion => 3.6,
		       cvsRevision =>  '$Revision: 3413 $',
		       name => ref($self),
		       argsDeclaration   => $argsDeclaration,
		       documentation     => $documentation
		      });

    return $self;
}

sub run {
    my ($self) = @_;

    my $name = $self->getArg('name');
    my $version = $self->getArg('version');
    my $parameters = $self->getArg('parameters');

   my $am = GUS::Model::ApiDB::AnalysisMethodInvocation->
     new({'name' => $name,
	 'version' => $version,
	 'parameters' => $parameters,
	});

    $am->submit();
   return "Inserted 1 method into AnalysisMethodInvocation";
   }




sub undoTables {
  my ($self) = @_;

  return ('ApiDB.AnalysisMethodInvocation',
         );
}

1;
