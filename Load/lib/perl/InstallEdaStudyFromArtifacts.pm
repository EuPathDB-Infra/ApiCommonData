package ApiCommonData::Load::InstallEdaStudyFromArtifacts;

use strict;
use warnings;

use DBI;
use DBI qw(:sql_types);
use Time::HiRes qw ( time );
use JSON qw( decode_json );
use File::Copy;
use strict;

my $SQLLDR_STREAM_SIZE = 512000;
my $SQLLDR_ROWS = 5000;
my $SQLLDR_BINDSIZE = 2048000;
my $SQLLDR_READSIZE = 1048576;

sub new {
    my ($class, $hash) = @_;

    my @requiredVars = ('DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_PLATFORM', 'DB_USER', 'DB_PASS', 'DB_SCHEMA', 'DATA_FILES', 'INPUT_DIR');
    foreach(@requiredVars) {
        unless($hash->{$_}) {
            die "Missing required value for:   $_"
        }
    }

    my $self = bless $hash, $class;

    my $dbPlatform = $self->getDbPlatform();
    my $dbHost = $self->getDbHost();
    my $dbPort = $self->getDbPort();
    my $dbName = $self->getDbName();
    my $dbUser = $self->getDbUser();
    my $dbPass = $self->getDbPass();

    my $dbh;
    unless ($self->isDryRun) {
        my $connectString = "dbi:${dbPlatform}://${dbHost}:${dbPort}/${dbName}";
        $dbh = DBI->connect($connectString, $dbUser, $dbPass)
            || die "Couldn't connect to database: " . DBI->errstr;
    }
    $dbh->{RaiseError} = 1;
    $dbh->{AutoCommit} = 1;

    $self->setDbh($dbh);

    return $self;
}

sub getDataFilesDir { $_[0]->{DATA_FILES} }
sub getInputDir { $_[0]->{INPUT_DIR} }
sub getUserDatasetId { $_[0]->{USER_DATASET_ID} }

sub getDbHost { $_[0]->{DB_HOST} }
sub getDbPort { $_[0]->{DB_PORT} }
sub getDbName { $_[0]->{DB_NAME} }
sub getDbPlatform { $_[0]->{DB_PLATFORM} }
sub getDbUser { $_[0]->{DB_USER} }
sub getDbPass { $_[0]->{DB_PASS} }
sub getDbSchema { $_[0]->{DB_SCHEMA} }

sub getDbh { $_[0]->{_DBH} }
sub setDbh { $_[0]->{_DBH} = $_[1] }

sub hasUserDatasetId { defined $_[0]->{USER_DATASET_ID} ? 1 : 0 }
sub isDryRun {defined $_[0]->{DRYRUN} ? 1 : 0 }

sub getConfigsArrayFromInstallJsonFile {
    my ($self) = @_;

    my $installJsonFile = $self->getInstallJsonFile();

    open my $fh, '<', $installJsonFile or die "error opening $installJsonFile: $!";
    my $jsonString = do { local $/; <$fh> };
    return decode_json($jsonString);
}

sub getIndxTableSpace {
    my ($self) = @_;
    return $self->getDbPlatform() eq 'Oracle'? " tablespace indx" : "";
}


sub getInstallJsonFile {
    my ($self) = @_;

    my $inputDir = $self->getInputDir();

    my $installJsonFile = "$inputDir/install.json";

    die "No install.json file found." unless -e $installJsonFile;

    return $installJsonFile;
}


sub uninstallData {
    my ($self) = @_;

    my $installJsonFile = $self->getInstallJsonFile();
    my $userDatasetId = $self->getUserDatasetId();

    my $schema = $self->getDbSchema();
    my $datasetDir = $self->getDataFilesDir();
    my $dbh = $self->getDbh();

    # check if already uninstalled
    if (!(-e $installJsonFile) && $self->hasUserDatasetId()) {
        my $sql = "select count(*) from $schema.study where user_dataset_id = '$userDatasetId'";
        my $sth = $dbh->prepare($sql);
        $sth->execute();
        my ($studyRowPresent) = $sth->fetchrow_array;  # uh oh... no install.json but not removed fully from db
        die "Missing file $datasetDir/install.json.  Cannot uninstall\n" if ($studyRowPresent);
        print STDERR "Dataset not present.  Nothing to uninstall\n";
        exit 0;
    }

    my $configsArray = $self->getConfigsArrayFromInstallJsonFile();

    # drop views
    foreach my $config (@$configsArray) {
        next if $config->{type} ne 'view';
        $self->dropTableOrView($dbh, 'view', "$schema.$config->{name}");
    }

    # drop tables
    foreach my $config (@$configsArray) {
        next if $config->{type} ne 'table' || $config->{is_preexisting_table} ;
        $self->dropTableOrView($dbh, 'table', "$schema.$config->{name}");
    }

    # TODO fix below

#     # delete rows from shared tables
#     my $sql = "
# delete from $schema.entitytypegraph
# where study_stable_id in (
#  select stable_id from $schema.study where user_dataset_id = '$userDatasetId'
# )";
#     print STDERR "RUNNING SQL: $sql\n\n";
#     $dbh->do($sql) || die "Failed running sql: $sql\n";

#     $sql = "delete from $schema.study where user_dataset_id = '$userDatasetId'";
#     print STDERR "RUNNING SQL: $sql\n\n";
#     $dbh->do($sql) || die "Failed running sql: $sql\n";

#     # finally, remove UD data dir.  leave this for last, to retain install.json if there are any errors
#     if (-e "$datasetDir/install.json") {
#         unlink("$datasetDir/install.json") || die "Can't remove file '$datasetDir/install.json'\n";
#     }
#     if (-e $datasetDir) {
#         rmdir($datasetDir) || die "Can't remove UD dir '$datasetDir'\n";
#     }

}


sub dropTableOrView {
  my ($self, $tableOrView, $thing) = @_;

  my $dbh = $self->getDbh();

  if ($ENV{DB_PLATFORM} eq 'Oracle') {
    $dbh->{RaiseError} = 0; $dbh->{PrintError} = 0;
    my $sql = "drop $tableOrView $thing";
    print STDERR "RUNNING SQL: $sql\n\n";
    my $status = $dbh->do($sql);
    # ignore error that table or view does not exist (ORA-00942)
    die "Error trying to drop $tableOrView $thing " . $DBI::errstr unless ($status || $DBI::errstr =~ /ORA-00942/);
    $dbh->{RaiseError} = 1; $dbh->{PrintError} = 1;
  } else {
    my $sql = "drop $tableOrView if exists $thing";  # pg offers the sensible thing
    print STDERR "RUNNING SQL: $sql\n\n";
    $dbh->do($sql);
  }
}

sub installData {
    my ($self) = @_;


    my $installJsonFile = $self->getInstallJsonFile();
    my $configsArray = $self->getConfigsArrayFromInstallJsonFile();

    my $inputDir = $self->getInputDir();

    # validate that we have all needed files
    foreach my $config (@$configsArray) {
        next unless $config->{type} eq 'table';
        my $cacheFile = "$inputDir/$config->{name}.cache";
        die "Can't find $cacheFile" unless -e "$cacheFile";
    }

    # Create data files dir containing the install.json file _before_ loading data
    # IN VDI Context this will be DATA_FILES Environment variable and will be made available to uninstall.
    $self->createDatasetDir($installJsonFile);

    # loop through tables.  if not preexisting, create table.  use bulk loader to load rows
    foreach my $config (@$configsArray) {
        next unless $config->{type} eq 'table';
        if ($config->{is_preexisting_table}) {
            $self->loadTable($config)
        } else {
            $self->createTable($config);
            $self->bulkLoadTable($config);
        }
    }

    # loop through indexes
    foreach my $config (@$configsArray) {
        next unless $config->{type} eq 'index';
        $self->createIndex($config);
    }

    # loop through views
    foreach my $config (@$configsArray) {
        next unless $config->{type} eq 'view';
        $self->createView($config);
    }



}


# Creates an install directory for the dataset being installed, copying into it
# the install.json file that is needed by the uninstall script to delete the
# dataset's tables from a target app database.
sub createDatasetDir {
  my ($self, $inputInstallJsonPath) = @_;

  #my $datasetDir = "$ENV{DATA_FILES}";
  my $datasetDir = $self->getDataFilesDir();;

  if (-e $datasetDir) {
    die "dataset directory $datasetDir already exists\n";
  }

  my $targetInstallJsonPath = "$datasetDir/install.json";

  mkdir($datasetDir) || die "failed to create dataset dir $datasetDir\n";
  chmod(0775, $datasetDir) || die "failed to chmod $datasetDir\n";

  copy($inputInstallJsonPath, $targetInstallJsonPath) || die "failed to copy $inputInstallJsonPath to $datasetDir\n";
  chmod(0664, $targetInstallJsonPath) || die "failed to chmod $targetInstallJsonPath\n";
}


# we don't use bulk loading for these tables because we insert very few rows, and they have macros
sub loadTable {
  my ($self, $tableConfig) = @_;

  my $inputDir = $self->getInputDir();
  my $dbh = $self->getDbh();
  my $schema = $self->getDbSchema();
  my $userDatasetId = $self->getUserDatasetId();
  my $platform = $self->getDbPlatform();


  my @colNames;
  my $fields = $tableConfig->{fields};
  my $tableName = $tableConfig->{name};
  print STDERR "Loading table $tableName\n";
  foreach my $field (@$fields) {
    push(@colNames, $field->{name});
  }
  my $colNamesStr = join(", ", @colNames);
  my $file = "$inputDir/$tableName.cache";
  open my $info, $file or die "Could not open $file: $!";

  my @values;
  while( my $line = <$info>) {
    # Strip any trailing newlines
    $line =~ s/\n+$//;
    # Use -1 as the last arg to preserve trailing empty columns
    my @v = split(/\t/, $line, -1);
    my @values;
    my $count = 0;
    foreach my $v (@v) {
      push(@values, $self->mapColValues($v, $fields->[$count]->{type}));
      $count += 1;
    }
    my $valuesStr = join(", ", @values);
    my $sql = "INSERT INTO $schema.$tableName ($colNamesStr) SELECT $valuesStr";
    $sql .= " FROM DUAL" if $platform eq "Oracle";
    $dbh->do($sql) unless $self->isDryRun();
  }
  $dbh->commit() unless $self->isDryRun();;
  close $info;
}

# only used for preexisting tables
sub mapColValues {
  my ($self, $valueFromFile, $colType) = @_;

  my $userDatasetId = $self->getUserDatasetId();
  my $schema = $self->getDbSchema();
  my $platform = $self->getDbPlatform();

  if ($valueFromFile eq '@USER_DATASET_ID@') { "'$userDatasetId'"  }
  if ($valueFromFile eq '@STUDY_ID@') { return $platform eq 'Oracle'? "$schema.study_sq.nextval" : "nextval($schema.study_sq)"; }
  if ($valueFromFile eq '@MODIFICATION_DATE@') { return "SYSDATE" ; }
  if ($valueFromFile eq '@ENTITY_TYPE_GRAPH_ID@') { return $platform eq 'Oracle'? "$schema.entitytypegraph_sq.nextval" : "nextval($schema.entitytypegraph_sq)"; }
  if (($colType eq 'SQL_NUMBER' or $colType eq 'SQL_DATE') and $valueFromFile eq "")  { return "NULL"; }
  if ($colType eq 'SQL_VARCHAR' or $colType eq 'SQL_DATE') { return "'$valueFromFile'"; }
  return $valueFromFile;
}

sub createTable {
    my ($self, $tableConfig) = @_;

    my $dbh = $self->getDbh();
    my $schema = $self->getDbSchema();

    my $tableName = "$schema.$tableConfig->{name}";
    print STDERR "Creating table $tableName\n";
    my $cols = &createColumns($tableConfig);

    my $create = "
CREATE TABLE $tableName (
$cols
)
";
    $dbh->do($create) unless $self->isDryRun();

    my $grantVdiW = "GRANT INSERT, SELECT, UPDATE, DELETE on $tableName to vdi_w";
    $dbh->do($grantVdiW) unless $self->isDryRun();

    my $grantGusR = "GRANT SELECT on $tableName to gus_r";
    $dbh->do($grantGusR) unless $self->isDryRun();
}


sub bulkLoadTable {
    my ($self, $tableConfig) = @_;

    my $inputDir = $self->getInputDir();
    my $platform = $self->getDbPlatform();
    my $dbUser = $self->getDbUser();
    my $dbPassword = $self->getDbPass();
    my $dbHost = $self->getDbHost();
    my $dbPort = $self->getDbPort();
    my $dbName = $self->getDbName();
    my $schema = $self->getDbSchema();

    print STDERR "Bulk loading table $tableConfig->{name}\n";
    if ($platform eq 'Oracle') {
        my $controlFileName = $tableConfig->{name} . '.ctl';
        my $dataFileName = "$inputDir/" . $tableConfig->{name} . '.cache';
        my $logFileName = $tableConfig->{name} . '.log';
        my $direct = $tableConfig->{is_preexisting_table}? 0 : 1;
        &writeSqlloaderCtl($tableConfig->{fields}, $schema, $tableConfig->{name}, $controlFileName, $dataFileName, !$direct);
        my $cmdLine = &getSqlLdrCmdLine($dbUser, $dbPassword, $dbHost, $dbPort, $dbName, $controlFileName, $logFileName, $direct);

        unless ($self->isDryRun()) {
            if (system($cmdLine)) {
                print STDERR ">>> sqlldr execution failed: $!\n\n";

                $cmdLine =~ s/\Q$dbPassword/******/gi;
                print STDERR ">>> sqlldr failed command: $cmdLine\n\n";

                print STDERR ">>> sqlldr $controlFileName file content\n\n";

                open(LF, $controlFileName);
                while (my $ctlLine = <LF>) {
                    print STDERR "$ctlLine";
                }
                close(LF);

                my $logFileName = $tableConfig->{name} . ".log";

                if (-f $logFileName) {
                    print STDERR ">>> sqlldr $logFileName file content\n\n";

                    open(LF, $logFileName);
                    while (my $logLine = <LF>) {
                        print STDERR "$logLine";
                    }
                    close(LF);
                }

                my $badFileName = $tableConfig->{name} . ".bad";

                if (-f $badFileName) {
                    print STDERR ">>> sqllder $badFileName file content\n\n";

                    open(LF, $badFileName);
                    while (my $badLine = <LF>) {
                        print STDERR "$badLine";
                    }
                    close(LF);
                }

                die "Error running sqlloader";
            }
        }
    }
    else {
        die "Bulk Loader not yet supported for non oracle platform"
    }
}

sub createIndex {
    my ($self, $indexConfig) = @_;

    my $dbh = $self->getDbh();
    my $schema = $self->getDbSchema();
    my $indxTableSpace = $self->getIndxTableSpace();

    my $indexName = "$schema.$indexConfig->{name}";
    my $colArray = $indexConfig->{orderedColumns};
    my $cols = join(", ", @$colArray);
    my $createIndex = "CREATE INDEX $indexName on $schema.$indexConfig->{tableName} ($cols) $indxTableSpace";
    $dbh->do($createIndex) unless $self->isDryRun();
}

sub createView {
    my ($self, $viewConfig) = @_;

    my $dbh = $self->getDbh();
    my $schema = $self->getDbSchema();
    
    my $viewName = "$schema.$viewConfig->{name}";
    my $def = $viewConfig->{definition};
    $def =~ s/\@SCHEMA\@/$schema/g;
    my $createView = "CREATE VIEW $viewName as $def";
    $dbh->do($createView) unless $self->isDryRun();
}





# STATIC METHODS
sub writeSqlloaderCtl {
    my ($orderedFields, $schema, $tableName, $ctlFileName, $dataFileName, $append) = @_;

    my @colSpecs;
    foreach my $field (@$orderedFields) {
        my $colSpec;
        if ($field->{type} eq 'SQL_VARCHAR') { $colSpec = "CHAR ($field->{maxLength})"; }
        elsif ($field->{type} eq 'SQL_DATE') { $colSpec = "DATE 'yyyy-mm-dd hh24:mi:ss'"; }
        elsif ($field->{type} eq 'SQL_NUMBER')  { $colSpec =  "CHAR"; }  #use default here for numbers
        else { die "unrecognized SQL type: " + $field->{type}}

        push(@colSpecs, "$field->{name} $colSpec");
    }

    my $colSpecsStr = join(",\n", @colSpecs);
    my $appendStr = $append? "APPEND" : "";
    open(CTL, ">$ctlFileName") || die "Can't open '$ctlFileName' for writing";
    print CTL <<"EOF";
     LOAD DATA
     CHARACTERSET UTF8
     LENGTH SEMANTICS CHAR
     INFILE '$dataFileName'
     $appendStr
     INTO TABLE $schema.$tableName
     REENABLE DISABLED_CONSTRAINTS
     FIELDS TERMINATED BY '\\t'
     TRAILING NULLCOLS
    ($colSpecsStr
    )
EOF
    close(CTL);
}

sub createColumns {
    my ($tableConfig) = @_;

    my @colSpecs;
    my $fields = $tableConfig->{fields};
    foreach my $field (@$fields) {
        my $colSpec = $field->{name};
        if ($field->{type} eq 'SQL_VARCHAR') {
            if ($field->{maxLength} > 4000) { $colSpec .= " CLOB"; }
            else { $colSpec .= " VARCHAR" . ($field->{maxLength} eq 'NA'? "" : "($field->{maxLength})"); }
        } elsif ($field->{type} eq 'SQL_DATE') {
            $colSpec .= " DATE";
        } elsif ($field->{type} eq 'SQL_NUMBER')  {
            $colSpec .= " NUMBER" . ($field->{prec} eq 'NA'? "" : "($field->{prec})");
        } else { die "unrecognized SQL type: " + $field->{type}}
        $colSpec .= $field->{isNullable} eq 'YES'? "" : " NOT NULL";
        push(@colSpecs, $colSpec);
    }
    return join(",\n", @colSpecs);
}

# sqlldr userid=dbuser@\"\(description=\(address=\(host=remote.db.com\)\(protocol=tcp\)\(port=1521\)\)\(connect_data=\(sid=dbsid\)\)\)\"/dbpass control=controlfilename.ctl data=data.csv
sub getSqlLdrCmdLine {
    my ($login, $password, $host, $port, $dbname, $controlFileName, $logFileName, $direct) = @_;

    my $connectStr = "\"(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(Host=$host)(Port=$port))(CONNECT_DATA=(SERVICE_NAME=$dbname)))\"";

    my $cmd = "sqlldr '$login/$password\@$connectStr' control=$controlFileName errors=0 discardmax=0 log=$logFileName ";
    $cmd .= $direct?
        "streamsize=512000 direct=TRUE" :
        "rows=5000 bindsize=2048000 readsize=1048576";

    return $cmd . ' >/dev/null 2>&1';
}




1;
