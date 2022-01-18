use strict;
use warnings;

use lib "$ENV{GUS_HOME}/lib/perl";

use Test::More;
use YAML;
use List::Util qw/uniq/;

use File::Temp qw/tempdir/;
use File::Slurp qw/write_file/;
use ApiCommonData::Load::MBioResultsDir;


use CBIL::ISA::StudyAssayEntity::Source;
use CBIL::ISA::StudyAssayEntity::Assay;
# there are also requires

my $dir = tempdir(CLEANUP => 1);
my $study = "datasetName";

write_file("$dir/$study.16sv1v3.lineage_abundance.tsv", <<"EOF");
	s1	s2
k;p;c;o;f;g;s	11111.0	12111.0
different_kingdom	13111.0	14111.0
yet_different_kingdom	1111.0	
EOF

my $name16sv3v5 = "XXXv3v5";
write_file("$dir/$study.$name16sv3v5.lineage_abundance.tsv", <<"EOF");
	s1
different_kingdom	23222.0
EOF

write_file("$dir/$study.wgs.lineage_abundance.tsv", <<"EOF");
	s1	s2
k__K|p__P|c__C|o__O|f__F|g__G|s__S	15111.0	16111.0
k__DifferentKingdom	0.1	0.2
k__yet_different_kingdom	1111.0	0
EOF

write_file("$dir/$study.wgs.level4ec.tsv", <<"EOF");
	s1	s2
UNGROUPED	0.1	0.1
1.1.1.103: L-threonine 3-dehydrogenase|g__Escherichia.s__Escherichia_coli	17111.0	18111.0
1.1.1.103: L-threonine 3-dehydrogenase|unclassified	19111.0	20111.0
1.1.1.103: L-threonine 3-dehydrogenase	21111.0	22111.0
7.2.1.1: NO_NAME	23111.0	24111.0
8.2.1.1: NO_NAME	23111.0	0.0
EOF

write_file("$dir/$study.wgs.pathway_abundance.tsv", <<"EOF");
	s1	s2
ANAEROFRUCAT-PWY: homolactic fermentation	25111.0	26111.0
ANAEROFRUCAT-PWY: homolactic fermentation|g__Escherichia.s__Escherichia_coli	27111.0	28111.0
ANAEROFRUCAT-PWY: homolactic fermentation|unclassified	29111.0	30111.0
BNAEROFRUCAT-PWY: homolactic fermentation|unclassified	29111.0	0.0
EOF

write_file("$dir/$study.wgs.pathway_coverage.tsv", <<"EOF");
	s1	s2
ANAEROFRUCAT-PWY: homolactic fermentation	0.31111	0.32111
ANAEROFRUCAT-PWY: homolactic fermentation|g__Escherichia.s__Escherichia_coli	0.33111	0.34111
ANAEROFRUCAT-PWY: homolactic fermentation|unclassified	0.35111	0.36111
BNAEROFRUCAT-PWY: homolactic fermentation|unclassified	0.35111	0.0
EOF

my $getAddMoreData =ApiCommonData::Load::MBioResultsDir->new($dir, {ampliconTaxa => "lineage_abundance.tsv", wgsTaxa => "lineage_abundance.tsv", level4ECs => "level4ec.tsv", pathwayAbundances => "pathway_abundance.tsv", pathwayCoverages => "pathway_coverage.tsv", eukdetectCpms => "eukdetect.lineage_abundance.tsv" })->toGetAddMoreData;

# this is the SimpleXml parse of one study in i_Investigation.xml
my $studyXml = {
  dataset => [$study],
  node => {
    '16sv1v3' => {
      'isaObject' => 'Assay',
      'suffix' => '16sv1v3',
      'type' => 'Amplicon sequencing assay'
    },
    $name16sv3v5 => {
      'isaObject' => 'Assay',
      'suffix' => $name16sv3v5,
      'type' => 'Amplicon sequencing assay'
    },
    'Sample' => {
      'type' => 'sample from organism'
    },
    'Source' => {
      'suffix' => 'Source',
      'type' => 'host'
    },
    'wgs' => {
      'isaObject' => 'Assay',
      'suffix' => 'wgs',
      'type' => 'Whole genome sequencing assay'
    }
  }
};
my $addMoreData = $getAddMoreData->($studyXml);


my $s1source = bless {_value => "s1 (Source)"}, 'CBIL::ISA::StudyAssayEntity::Source';
is_deeply($addMoreData->($s1source), {}, 's1 Source');

my $spareAssay = bless {_value => "s3 (Assay)"}, 'CBIL::ISA::StudyAssayEntity::Assay';
is_deeply($addMoreData->($spareAssay), {}, 's3 (Assay)');

sub okAmpliconKeys {
  my ($name) = @_;
  my $in =  bless {_value => $name}, 'CBIL::ISA::StudyAssayEntity::Assay';
  my $result = $addMoreData->($in);
  subtest $name => sub {
    ok($result->{$_}, "Result has key: $_") for qw /relative_abundance_c relative_abundance_f relative_abundance_g relative_abundance_k relative_abundance_o relative_abundance_p relative_abundance_s alpha_diversity_shannon alpha_diversity_inverse_simpson/; 
  };
};

okAmpliconKeys("s1 ($name16sv3v5)");
okAmpliconKeys("s1 (16sv1v3)");
okAmpliconKeys("s2 (16sv1v3)");
sub okWgsKeys {
  my ($name) = @_;
  my $in =  bless {_value => $name}, 'CBIL::ISA::StudyAssayEntity::Assay';
  my $result = $addMoreData->($in);
  subtest $name => sub {
    ok($result->{$_}, "Result has key: $_") for qw/relative_abundance_c relative_abundance_f relative_abundance_g relative_abundance_k relative_abundance_o relative_abundance_p relative_abundance_s function_level4EC pathway_abundance pathway_abundance_species pathway_coverage pathway_coverage_species alpha_diversity_shannon alpha_diversity_inverse_simpson/;
  };
}
okWgsKeys("s1 (wgs)");


done_testing;
