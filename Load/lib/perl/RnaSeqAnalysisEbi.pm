package ApiCommonData::Load::RnaSeqAnalysisEbi;
use lib "$ENV{GUS_HOME}/lib/perl";
use base qw(CBIL::StudyAssayResults::DataMunger);


use strict;
use CBIL::StudyAssayResults::Error;
use ApiCommonData::Load::RnaSeqCounts;

use ApiCommonData::Load::IntronJunctionsEbi;
use ApiCommonData::Load::DeseqAnalysisEbi;
use Data::Dumper;


my $OUTPUT_FILE_BASE = "profiles";

#-------------------------------------------------------------------------------

sub getProfileSetName          { $_[0]->{profileSetName} }
sub getSamples                 { $_[0]->{samples} }

sub getIsStrandSpecific        { $_[0]->{isStrandSpecific} }
sub getSeqIdPrefix             { $_[0]->{seqIdPrefix}}
sub getPatch                   {$_[0]->{patch} }

sub getSkipDeSeq                { $_[0]->{skipDeSeq} }
#-------------------------------------------------------------------------------
sub new {
    my ($class, $args) = @_;
    my $requiredParams = [
	'samples',
	'profileSetName',
	];
    my $self = $class->SUPER::new($args, $requiredParams);
    
    if(my $outputPrefix = $self->getOutputFile()) {
	    $OUTPUT_FILE_BASE = $outputPrefix . $OUTPUT_FILE_BASE;
    }
    
    return $self;
}

sub munge {
    my ($self) = @_;
    
    my $featureType = 'genes';
    my @valueTypes = ('tpm');
    my $makePercentiles = 1;
    my $isStrandSpecific = $self->getIsStrandSpecific();
    my $samplesHash = $self->groupListHashRef($self->getSamples());
    my $profileSetName = $self->getProfileSetName();


    my $skipDeSeq = $self->getSkipDeSeq();
    my $patch = $self->getPatch();
    
    if (! $patch) {
        foreach my $sampleName (keys %$samplesHash) {
            # this location to be used for the config and output
            my $mainDirectory = $self->getMainDirectory();
            # input files in here TODO change to results
            my $mainDir = "$mainDirectory/results";
            my $intronJunctions = ApiCommonData::Load::IntronJunctionsEbi->new({sampleName => $sampleName,
                                                                                inputs => $samplesHash->{$sampleName},
                                                                                mainDirectory => $mainDir,
                                                                                profileSetName => $profileSetName,
                                                                                samplesHash => $samplesHash,
                                                                                sourceIdPrefix => $self->getSeqIdPrefix,
                                                                                suffix => 'junctions.tab'});
            $intronJunctions->setProtocolName("GSNAP/Junctions");
            $intronJunctions->setDisplaySuffix(" [junctions]");
            $intronJunctions->setTechnologyType($self->getTechnologyType());
            $intronJunctions->setConfigFilePath("$mainDirectory/analysis_output");
            my $cleanSampleName = $intronJunctions->getSampleName();
            $cleanSampleName =~ s/\s/_/g; 
            $cleanSampleName=~ s/[\(\)]//g;
            $intronJunctions->setOutputFile($mainDirectory . "/analysis_output/" . $cleanSampleName . "_results" . $intronJunctions->getSuffix());

            $intronJunctions->munge();
        }
    }

    foreach my $valueType (@valueTypes) {

        my $quantificationType = 'htseq-union';

        if($isStrandSpecific) {
            $self->makeProfiles('firststrand', $featureType, $quantificationType, $valueType, $makePercentiles, 1);
            $self->makeProfiles('secondstrand', $featureType, $quantificationType, $valueType, $makePercentiles, 1);

            $self->makeProfiles('firststrand', $featureType, $quantificationType, $valueType, $makePercentiles, 0);
            $self->makeProfiles('secondstrand', $featureType, $quantificationType, $valueType, $makePercentiles, 0);

        }
        else {
            $self->makeProfiles('unstranded', $featureType, $quantificationType, $valueType, $makePercentiles, 1);
            $self->makeProfiles('unstranded', $featureType, $quantificationType, $valueType, $makePercentiles, 0);
        }
        }
    return;
}

sub makeProfiles {
    my ($self, $strand, $featureType, $quantificationType, $valueType, $makePercentiles, $isUnique) = @_;

    my $samples = $self->getSamples();

    my $profileSetName = $self->getProfileSetName();

    my $isStrandSpecific = $self->getIsStrandSpecific() ? $self->getIsStrandSpecific() : 'FALSE';

    # cleanup for non unique
    if(!$isUnique) {
      $valueType = "nonunique.$valueType";
      $makePercentiles = 0;
    }

    my $outputFile = "$OUTPUT_FILE_BASE.$featureType.$quantificationType.$strand.$valueType";

    # this location to be used for the config
    my $mainDirectory = $self->getMainDirectory();
    
    my $profile = ApiCommonData::Load::RnaSeqCounts->
	new({mainDirectory => $mainDirectory,
	     outputFile => "$mainDirectory/analysis_output/$outputFile",
	     makePercentiles => $makePercentiles,
	     isLogged => 0,
	     fileSuffix => "$featureType.$quantificationType.$strand.$valueType",
	     samples => $samples,
	     profileSetName => $profileSetName,
         sampleNameAsDir => 1,
         isUnique => $isUnique,
         strand => $strand,
	    });

    my $header = 0;

    $profile->setHasHeader($header);

    # protocolName will be TPM for normalised values or HTSeq for counts
    my $protocolName = 'HTSeq';

    $profile->setProtocolName("HISAT2/$protocolName");

    $profile->addProtocolParamValue('Strand', $strand);
    $profile->addProtocolParamValue('FeatureType', $featureType);
    $profile->addProtocolParamValue('QuantificationType', $protocolName);


    if ($protocolName eq 'HTSeq') {
        $quantificationType =~ /^htseq-(.+)$/;
        my $mode = $1;
        $profile->addProtocolParamValue('Mode', $mode);
    }

    if($isUnique) {
      $profile->setDisplaySuffix(" [$quantificationType - $strand - $valueType - unique]");
    }
    else {
      $profile->setDisplaySuffix(" [$quantificationType - $strand - $valueType - nonunique]");
    }

    $profile->setTechnologyType($self->getTechnologyType());

    $profile->setConfigFilePath("$mainDirectory/analysis_output");
    $profile->munge();
    
    return($outputFile);
}

1;
