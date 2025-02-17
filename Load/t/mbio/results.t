use strict;
use warnings;

use lib "$ENV{GUS_HOME}/lib/perl";

use ApiCommonData::Load::MBioResults;
use Test::More;
use Test::Exception;
use YAML;
use List::Util qw/uniq/;

my $t = bless {}, 'ApiCommonData::Load::MBioResults';

my %args;

dies_ok {$t->readData(\%args) } "Required: dataset name";
$args{datasetName} = "Test dataset";


dies_ok {$t->readData(\%args) } "Required: some files";


dies_ok {$t->readData({%args, ampliconTaxaPath => "/bad/path"}) } "Required: file args are openable";
dies_ok {$t->readData({%args, ampliconTaxaPath => \""}) } "Required: file args have stuff in them";

my $ampliconTaxaPath=<<"EOF";
	s1	s2
k;p;c;o;f;g;s	11111.0	12111.0
different_kingdom	13111.0	14111.0
yet_different_kingdom	1111.0	
EOF
my $badAmpliconTaxaPath = $ampliconTaxaPath.'\nbad line no tabs';
dies_ok {$t->readData({%args, ampliconTaxaPath => \$badAmpliconTaxaPath}) } "Bad files are bad";

$args{ampliconTaxaPath} = \$ampliconTaxaPath;

lives_ok {$t->readData({%args}) } "Amplicon files have stuff";

my $wgsTaxaPath=<<"EOF";
	s1	s2
k__K|p__P|c__C|o__O|f__F|g__G|s__S	15111.0	16111.0
k__DifferentKingdom	0.1	0.2
k__yet_different_kingdom	1111.0	0
EOF

$args{wgsTaxaPath} = \$wgsTaxaPath;
dies_ok {$t->readData({%args}) } "WGS files need ECs and pathways";

my $level4ECsPath=<<"EOF";
	s1	s2
UNGROUPED	0.1	0.1
1.1.1.103: L-threonine 3-dehydrogenase|g__Escherichia.s__Escherichia_coli	17111.0	18111.0
1.1.1.103: L-threonine 3-dehydrogenase|unclassified	19111.0	20111.0
1.1.1.103: L-threonine 3-dehydrogenase	21111.0	22111.0
7.2.1.1: NO_NAME	23111.0	24111.0
8.2.1.1: NO_NAME	23111.0	0.0
EOF

my $pathwayAbundancesPath=<<"EOF";
	s1	s2
ANAEROFRUCAT-PWY: homolactic fermentation	25111.0	26111.0
ANAEROFRUCAT-PWY: homolactic fermentation|g__Escherichia.s__Escherichia_coli	27111.0	28111.0
ANAEROFRUCAT-PWY: homolactic fermentation|unclassified	29111.0	30111.0
BNAEROFRUCAT-PWY: homolactic fermentation|unclassified	29111.0	0.0
EOF

my $pathwayCoveragesPath=<<"EOF";
	s1	s2
ANAEROFRUCAT-PWY: homolactic fermentation	0.31111	0.32111
ANAEROFRUCAT-PWY: homolactic fermentation|g__Escherichia.s__Escherichia_coli	0.33111	0.34111
ANAEROFRUCAT-PWY: homolactic fermentation|unclassified	0.35111	0.36111
BNAEROFRUCAT-PWY: homolactic fermentation|unclassified	0.35111	0.0
EOF

$args{level4ECsPath} = \$level4ECsPath;
$args{pathwayAbundancesPath} = \$pathwayAbundancesPath;
$args{pathwayCoveragesPath} = \$pathwayCoveragesPath;

lives_ok {$t->readData({%args}) } "WGS files have stuff";

(my $badPathwayCoveragesPath = $pathwayCoveragesPath) =~ s/s2/different_sample/;
dies_ok {$t->readData({%args, pathwayCoveragesPath => \$badPathwayCoveragesPath}) } "Sample names should match";


(my $secondBadPathwayCoveragesPath = $pathwayCoveragesPath) =~ s/Escher/different_artist/;
dies_ok {$t->readData({%args, pathwayCoveragesPath => \$secondBadPathwayCoveragesPath}) } "Rows should match";

done_testing;
