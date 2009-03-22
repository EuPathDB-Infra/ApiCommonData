package ApiCommonData::Load::TuningConfig::TuningRegistry;


use strict;
use ApiCommonData::Load::TuningConfig::Log;

sub new {
    my ($class, $dbh) = @_;
    my $self = {};
    $self->{dbh} = $dbh;
    bless($self, $class);

    return $self;
}

sub getInfoFromRegistry {
    my ($self) = @_;

    my $dbh = $self->{dbh};

    my $sql = <<SQL;
      select imi.instance_nickname, ti.instance_nickname, tf.subversion_url, tf.notify_emails
      from apidb.TuningInstance\@apidb.login_comment ti, apidb.TuningFamily\@apidb.login_comment tf,
           apidb.InstanceMetaInfo imi
      where ti.instance_nickname(+) =  imi.instance_nickname
        and ti.family_name = tf.family_name(+)
SQL

    my $stmt = $dbh->prepare($sql);
    $stmt->execute()
      or ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");

    ($self->{service_name}, $self->{instance_name}, $self->{subversion_url}, $self->{notify_emails})
      = $stmt->fetchrow_array();

    ApiCommonData::Load::TuningConfig::Log::addErrorLog("no tuning info found in registry for instance_nickname \"$self->{service_name}\".\n"
						       . "Use \"tuningMgrMgr -addInstance\" to add this instance to the registry.")
	if !defined $self->{subversion_url};
    $stmt->finish();
}

sub getSubversionUrl {
    my ($self) = @_;

    $self->getInfoFromRegistry() if !defined $self->{subversion_url};

    return($self->{subversion_url});
}

sub getNotifyEmails {
    my ($self) = @_;

    $self->getInfoFromRegistry() if !defined $self->{notify_emails};

    return($self->{notify_emails});
}

sub getInstanceName {
    my ($self) = @_;

    $self->getInfoFromRegistry() if !defined $self->{instance_name};

    return($self->{instance_name});
}

sub setLastUpdater {
    my ($self) = @_;

    my $dbh = $self->{dbh};
    my $processInfo = ApiCommonData::Load::TuningConfig::Log::getProcessInfo();

    my $sql = <<SQL;
      update apidb.TuningInstance\@apidb.login_comment
      set last_updater = '$processInfo'
      where instance_nickname = (select instance_nickname from apidb.InstanceMetaInfo)
SQL

    $dbh->do($sql)
      or ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");
}

sub setLastChecker {
    my ($self) = @_;

    my $dbh = $self->{dbh};
    my $processInfo = ApiCommonData::Load::TuningConfig::Log::getProcessInfo();

    my $sql = <<SQL;
      update apidb.TuningInstance\@apidb.login_comment
      set last_checker = '$processInfo'
      where instance_nickname = (select instance_nickname from apidb.InstanceMetaInfo)
SQL

    $dbh->do($sql)
      or ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");
}

sub setOk {
    my ($self) = @_;

    my $dbh = $self->{dbh};
    my $processInfo = ApiCommonData::Load::TuningConfig::Log::getProcessInfo();

    my $sql = <<SQL;
      update apidb.TuningInstance\@apidb.login_comment
      set last_ok = sysdate, outdated_since = null
      where instance_nickname = (select instance_nickname from apidb.InstanceMetaInfo)
SQL

    $dbh->do($sql)
      or ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");
}

sub setOutdated {
    my ($self) = @_;

    my $dbh = $self->{dbh};
    my $processInfo = ApiCommonData::Load::TuningConfig::Log::getProcessInfo();

    my $sql = <<SQL;
      update apidb.TuningInstance\@apidb.login_comment
      set outdated_since = sysdate
      where instance_nickname = (select instance_nickname from apidb.InstanceMetaInfo)
SQL

    $dbh->do($sql)
      or ApiCommonData::Load::TuningConfig::Log::addErrorLog("\n" . $dbh->errstr . "\n");
}

1;
