#!/usr/bin/perl

use Getopt::Long;
use strict;
use lib "$ENV{GUS_HOME}/lib/perl";

use DBI;
use DBD::Oracle;
use CBIL::Util::PropertySet;

my (
    $projectName,
    $organismAbbrev,
    $organismFullName,
    $isAnnotatedGenome,
    $buildNumber,
    $genomeSource,
    $genomeVersion,
    $annotationSource,
    $annotationVersion,
    $pubMedId,
    $primaryContactId,
    $assemblyId,
    $bioprojectId,
    $ifWithNonNuclear,
    $ifWithCentromere,
    $ifPrintContactIdFile,
    $help);

&GetOptions(
	    'projectName=s' => \$projectName,
	    'organismAbbrev=s' => \$organismAbbrev,
            'organismFullName=s' => \$organismFullName,
	    'isAnnotatedGenome=s' => \$isAnnotatedGenome,
	    'buildNumber=s' => \$buildNumber,
	    'genomeSource=s' => \$genomeSource,
	    'genomeVersion=s' => \$genomeVersion,
	    'annotationSource=s' => \$annotationSource,
	    'annotationVersion=s' => \$annotationVersion,
	    'pubMedId=s' => \$pubMedId,
	    'primaryContactId=s' => \$primaryContactId,
	    'assemblyId=s' => \$assemblyId,
	    'bioprojectId=s' => \$bioprojectId,
	    'ifWithNonNuclear=s' => \$ifWithNonNuclear,
	    'ifWithCentromere=s' => \$ifWithCentromere,
	    'ifPrintContactIdFile=s' => \$ifPrintContactIdFile,
	    'help|h' => \$help,
	    );
&usage() if($help);
&usage("Missing a Required Argument") unless(defined $projectName && $organismAbbrev);


## printPresentTemplate
my $plainText = ($isAnnotatedGenome =~ /^y/i) ? "Genome Sequence and Annotation" : "Genome Sequence";

print "  <datasetPresenter name=\"$organismAbbrev\_primary_genome_RSRC\"\n";
print "                    projectName=\"$projectName\">\n";

print "    <displayName><![CDATA[$plainText]]></displayName>\n";  ## need change by $isAnnot
print "    <shortDisplayName></shortDisplayName>\n";
print "    <shortAttribution></shortAttribution>\n";
&printSummary();
&printDescription();

print "    <protocol><\/protocol>\n";
print "    <caveat><\/caveat>\n";
print "    <acknowledgement><\/acknowledgement>\n";
print "    <releasePolicy><\/releasePolicy>\n";

$genomeVersion = revertDate ($genomeVersion);

$annotationSource = $genomeSource if (!$annotationSource);
$annotationVersion = $genomeVersion if (!$annotationVersion);

&printHistory();
&printPrimaryContactId();
&printExternalLinks();
&printPubMedId();

($isAnnotatedGenome =~ /^y/i) ? &printAnnotatedGenome : &printUnAnnotatedGenome;

print "  </datasetPresenter>\n";

print printContactInformation($primaryContactId) if ($ifPrintContactIdFile =~ /^y/i);

##################### subroutine ###################
sub revertDate {
  my ($ver) = @_;
  my $after;

my %mons = qw(01 Jan
              02 Feb
              03 Mar
              04 Apr
              05 May
              06 Jun
              07 Jul
              08 Aug
              09 Sep
              10 Oct
              11 Nov
              12 Dec
);

  if ($ver =~ /(\d\d\d\d)\-(\d\d)\-(\d\d)/) {
    my $y = $1;
    my $m = $2;
    my $d = $3;
    $after = $mons{$m} . " " . $d . ", " . $y;
  } else {
    $after = $ver;
    print STDERR "ERROR: genomeVersion isn't configured\n";
  }

  return $after;
}

sub printAnnotatedGenome {
  my ($temp) = @_;

  if ($ifWithNonNuclear =~ /^y/i && $ifWithCentromere !~ /^y/i) {
    print "    <templateInjector className=\"org.apidb.apicommon.model.datasetInjector.AnnotatedGenomeWithNonNuclear\">\n";
  } elsif ($ifWithNonNuclear !~ /^y/i && $ifWithCentromere =~ /^y/i) {
    print "    <templateInjector className=\"org.apidb.apicommon.model.datasetInjector.AnnotatedGenomeCentromereTelomere\">\n";
  } elsif ($ifWithNonNuclear =~ /^y/i && $ifWithCentromere =~ /^y/i) {
    print "    <templateInjector className=\"org.apidb.apicommon.model.datasetInjector.AnnotatedGenomeCentromereWithNonNuclear\">\n";
  } else {
    print "    <templateInjector className=\"org.apidb.apicommon.model.datasetInjector.AnnotatedGenome\">\n";
  }

  print "      <prop name=\"isEuPathDBSite\">true<\/prop>\n";
  print "      <prop name=\"optionalSpecies\"><\/prop>\n";
  print "      <prop name=\"specialLinkDisplayText\"><\/prop>\n";
  print "      <prop name=\"updatedAnnotationText\"><\/prop>\n";
  print "      <prop name=\"isCurated\">false<\/prop>\n";
  print "      <prop name=\"specialLinkExternalDbName\"><\/prop>\n";
  print "      <prop name=\"showReferenceTranscriptomics\">false<\/prop>\n";
  print "    <\/templateInjector>\n";

  return 0;
}

sub printSummary {
  my ($id) = @_;
  print "    <summary><![CDATA[$plainText of ";
  &printOrganismFullName($organismFullName) if ($organismFullName);
  print "\n                  ]]></summary>\n";
  return 0;
}

sub printDescription {
  my ($id) = @_;
  print "    <description><![CDATA[\n";
  print "                    $plainText of ";
  &printOrganismFullName($organismFullName) if ($organismFullName);
  print "\n\n                  ]]><\/description>\n";
}

sub printPubMedId {

  if (!$pubMedId) {
    print "    <pubmedId>$pubMedId</pubmedId>\n";
  } else {
    my @ids = split (/\,/, $pubMedId);
    foreach my $id (@ids) {
      $id =~ s/\s+//g;
      print "    <pubmedId>$id</pubmedId>\n";
    }
  }
  return 0;
}

sub printPrimaryContactId {

  my $name = optimizedContactId ($primaryContactId);

  ($primaryContactId) ? print "    <primaryContactId>$name<\/primaryContactId>\n"
                      : print "    <primaryContactId>TODO<\/primaryContactId>\n";
  return 0;
}

sub optimizedContactId {
  my ($name) = @_;

  $name = lc ($name);
  $name =~ s/^\s+//;
  $name =~ s/\s+$//;
  $name =~ s/\s+/\./g;

  return $name;
}

sub printUnAnnotatedGenome {
  my ($temp) = @_;

  print "    <templateInjector className=\"org.apidb.apicommon.model.datasetInjector.UnannotatedGenome\"\/>\n";
  return 0;
}

sub printHistory {
  my ($bld, $source, $version) = @_;

  print "    <history buildNumber=\"$buildNumber\"\n";
  ($assemblyId) ? print "             genomeSource=\"INSDC\" genomeVersion=\"$assemblyId\"\n"
                : print "             genomeSource=\"$genomeSource\" genomeVersion=\"$genomeVersion\"\n";

  ($isAnnotatedGenome =~ /^y/i) ? print "             annotationSource=\"$annotationSource\" annotationVersion=\"$annotationVersion\"\/>\n"
                                : print "             annotationSource=\"\" annotationVersion=\"\"\/>\n";
  return 0;
}

sub printExternalLinks {
  my ($temp) = @_;

  print "    <link>\n";
  print "      <text>NCBI Bioproject<\/text>\n";
  ($bioprojectId) ? print "      <url>https:\/\/www.ncbi.nlm.nih.gov\/bioproject\/$bioprojectId<\/url>\n" : print "      <url><\/url>\n";
  print "    </link>\n";
  print "    <link>\n";
#  print "      <text>GenBank Assembly page<\/text>\n";
  ($assemblyId =~ /^GCF_/) ? print "      <text>RefSeq Assembly<\/text>\n" : print "      <text>GenBank Assembly<\/text>\n";
  ($assemblyId) ? print "      <url>https:\/\/www.ncbi.nlm.nih.gov\/assembly\/$assemblyId</url>\n" : print "      <url></url>\n";
  print "    </link>\n";

  return 0;
}

sub printOrganismFullName {
  my ($fullName) = @_;

  my @items = split (/\s/, $fullName);
  my $genus = shift @items;
  my $species = shift @items;
  my $strain = join (" ", @items);

  print "<i>$genus $species</i> $strain";

  return 0;
}
sub printContactInformation {
  my ($fullName) = @_;
  my $id = optimizedContactId ($fullName);

  print "\n\n\n";
  print "  <contact>\n";
  print "    <contactId>$id<\/contactId>\n";
  print "    <name>$fullName<\/name>\n";
  print "    <institution><\/institution>\n";
  print "    <email><\/email>\n";
  print "    <address\/>\n";
  print "    <city\/>\n";
  print "    <state\/>\n";
  print "    <zip\/>\n";
  print "    <country\/>\n";
  print "  <\/contact>\n";

  return 0;
}


sub usage {
  die
"
Usage: printPresenterXmlFile4Genome.pl --organismAbbrev tgonME49 --projectName ToxoDB --isAnnotatedGenome Y
                                       --organismFullName \"Toxoplasma gondii ME49\" --buildNumber 49

       printPresenterXmlFile4Genome.pl --organismAbbrev tgonRH88 --projectName ToxoDB --isAnnotatedGenome Y --organismFullName \"Toxoplasma gondii RH-88\"
                                       --buildNumber 50 --genomeSource GenBank --genomeVersion \"May 15, 2020\" --primaryContactId \"Hernan Lorenzi\"
                                       --assemblyId GCA_013099955.1 --bioprojectId PRJNA279557

where
  --organismAbbrev: required, the organism abbrev
  --projectName: required, project name, such as PlasmoDB, etc. in full name
  --isAnnotatedGenome: required, Yes|yes|Y|y, No|no|N|n
  --organismFullName: optional
  --buildNumber: optional
  --genomeSource: optional
  --genomeVersion: optional, e.g. Mar 21, 2015
  --annotationSource: optional
  --annotationVersion: optional, e.g. Mar 21, 2015
  --pubMedId: optional
  --primaryContactId: optional
  --assemblyId: optional
  --bioprojectId: optional
  --ifWithNonNuclear: optional, Yes|yes|Y|y, No|no|N|n, if include annotation for non-nuclear sequences (i.e. mitochondrial or apicoplast sequence)
  --ifWithCentromere: optional, Yes|yes|Y|y, No|no|N|n, if include annotation for centromere and/or telomere region
  --ifPrintContactIdFile: optional, Yes|yes|Y|y, No|no|N|n

";
}
