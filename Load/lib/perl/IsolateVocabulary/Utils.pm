package ApiCommonData::Load::IsolateVocabulary::Utils;

use strict;

use DBI;
use DBD::Oracle;
use CBIL::Util::PropertySet;

sub createDbh {
  my ($gusConfigFile) = @_;

  my @properties = ();
  my $gusconfig = CBIL::Util::PropertySet->new($gusConfigFile, \@properties, 1);

  my $u = $gusconfig->{props}->{databaseLogin};
  my $pw = $gusconfig->{props}->{databasePassword};
  my $dsn = $gusconfig->{props}->{dbiDsn};

  return DBI->connect($dsn, $u, $pw) or die DBI::errstr;
}


sub isValidType {
  my ($type) = @_;

  my @allowed = ('geographic_location',
                 'specific_host',
                 'isolation_source'
                );

  foreach(@allowed) {
    if($type eq $_) {
      return 1;
    }
  }
  return 0;
}


sub isIncluded {
  my ($self, $a, $v) = @_;

  unless($a) {
    return 0;
  }

  foreach(@$a) {
    return 1 if $v eq $_;
  }
  return 0;
}

1;
