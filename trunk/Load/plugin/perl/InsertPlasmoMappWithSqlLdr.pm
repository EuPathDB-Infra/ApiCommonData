package ApiCommonData::Load::Plugin::InsertPlasmoMappWithSqlLdr;
@ISA = qw(GUS::PluginMgr::Plugin);


use strict;

use GUS::Supported::GusConfig;
use GUS::PluginMgr::Plugin;

$| = 1;

# ---------------------------------------------------------------------------
# Load Arguments
# ---------------------------------------------------------------------------

sub getArgumentsDeclaration{
  my $argsDeclaration =
    [

     fileArg({ name           => 'dataFile',
               descr          => 'Sql loader input file',
               reqd           => 1,
               mustExist      => 1,
               format         => '',
               constraintFunc => undef,
               isList         => 0,
             }),
    ];
  return $argsDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purpose = "Inserts ApiDB.PlasmoMapp.";

  my $purposeBrief = "";

  my $tablesAffected = [['ApiDB.PlasmoMapp', 'One Row to Identify Malaria Promoter Predictor']];

  my $tablesDependedOn = [];

  my $howToRestart = "No restart";

  my $failureCases = "";

  my $notes = "";

  my $documentation = {purpose=>$purpose, purposeBrief=>$purposeBrief, tablesAffected=>$tablesAffected, tablesDependedOn=>$tablesDependedOn, howToRestart=>$howToRestart, failureCases=>$failureCases,notes=>$notes};

  return $documentation;
}

#--------------------------------------------------------------------------------

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self,$class);

  my $documentation = &getDocumentation();
  my $argumentDeclaration = &getArgumentsDeclaration();

  $self->initialize({requiredDbVersion => 3.6,
		             cvsRevision => '$Revision$',
                     name => ref($self),
                     revisionNotes => '',
                     argsDeclaration => $argumentDeclaration,
                     documentation => $documentation});

  return $self;
}

#--------------------------------------------------------------------------------

sub run {
  my ($self) = @_;

  my $dataFile = $self->getArg('dataFile');

  my $configFile = "$dataFile" . ".ctrl";
 
  my $logFile = "$dataFile" . ".log";

  $self->writeConfigFile($configFile,$dataFile);

  my $login       = $self->getConfig->getDatabaseLogin();

  my $password    = $self->getConfig->getDatabasePassword();

  my $dbiDsn      = $self->getConfig->getDbiDsn();

  my ($dbi, $type, $db) = split(':', $dbiDsn);

  system("sqlldr $login/$password\@$db control=$configFile log=$logFile") if($self->getArg('commit'));
    
  return "Processed lines from data files";
}

#--------------------------------------------------------------------------------
sub writeConfigFile {
  my ($self, $configFile, $dataFile) = @_;
  my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
  my @abbr = qw(JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC);
  my $modDate = sprintf('%2d-%s-%02d', $mday, $abbr[$mon], ($year+1900) % 100);
  my $database = $self->getDb();
  my $projectId = $database->getDefaultProjectId();
  my $userId = $database->getDefaultUserId();
  my $groupId = $database->getDefaultGroupId();
  my $algInvocationId = $database->getDefaultAlgoInvoId();
  my $userRead = $database->getDefaultUserRead();
  my $userWrite = $database->getDefaultUserWrite();
  my $groupRead = $database->getDefaultGroupRead();
  my $groupWrite = $database->getDefaultGroupWrite();
  my $otherRead = $database->getDefaultOtherRead();
  my $otherWrite = $database->getDefaultOtherWrite();

  open(CONFIG, "> $configFile") or die "Cannot open file $configFile For writing:$!";

  print CONFIG "LOAD DATA
INFILE '$dataFile'
APPEND
INTO TABLE ApiDB.PlasmoMapp
FIELDS TERMINATED BY '\\t'
TRAILING NULLCOLS
(na_sequence_id,
strand,
location,
value,
modification_date constant  \"$modDate \", 
user_read constant $userRead, 
user_write constant $userWrite, 
group_read constant $groupRead, 
group_write constant $groupWrite, 
other_read constant $otherRead, 
other_write constant $otherWrite, 
row_user_id constant $userId, 
row_group_id constant $groupId, 
row_project_id constant $projectId, 
row_alg_invocation_id constant $algInvocationId,
PLASMOMAPP_ID  \"ApiDB.PlasmoMapp_sq.nextval\"
)\n";
  close CONFIG;
}

sub getConfig {
  my ($self) = @_;

  if (!$self->{config}) {
    my $gusConfigFile = $self->getArg('gusconfigfile');
     $self->{config} = GUS::Supported::GusConfig->new($gusConfigFile);
   }

  $self->{config};
}

sub undoTables {
  my ($self) = @_;

  return ('ApiDB.PlasmoMapp');
}

1;

