package ApiCommonData::Load::RnaSeqCounts;
use base qw(CBIL::StudyAssayResults::DataMunger::ProfileFromSeparateFiles);

use locale;
use open ":std" => ":locale";

use File::Basename;
use File::Temp qw/ tempfile /;

use strict;
use Data::Dumper;

# override from superclass since config file will not be in the same location as the input
sub getConfigFilePath {
    return $_[0]->{_config_file_path};
}

sub getIsUnique { $_[0]->{isUnique} }

sub getStrand { $_[0]->{strand} }

sub getTpmFile { $_[0]->{tpmFile} }
sub setTpmFile { $_[0]->{tpmFile} = $_[1] }

sub getCountFile { $_[0]->{countFile} }
sub setCountFile { $_[0]->{countFile} = $_[1] }

sub setConfigFilePath {
    my ($self, $mainDir) =  @_;
    my $configFileBaseName = $self->getConfigFileBaseName();
    my $configFilePath = "$mainDir/$configFileBaseName";
    $self->{_config_file_path} = $configFilePath;
}

# override from Profiles.pm
# remove all the stuff related to microarrays
# Raw and TPM counts go into one file
sub writeRScript {
    my($self, $samples) = @_;

    my $tpmFile = $self->getTpmFile();
    my $countFile = $self->getCountFile();
    my $outputFile = $self->getOutputFile();
    my $pctOutputFile = $outputFile . ".pct";
    my $stdErrOutputFile = $outputFile . ".stderr";
    (my $countOutputFile = $outputFile) =~ s/tpm/counts/;

    my ($rfh, $rFile) = tempfile();
    my $makePercentiles = $self->getMakePercentiles() ? "TRUE" : "FALSE";
    my $makeStandardError = $self->getMakeStandardError() ? "TRUE" : "FALSE";
    # we only want to load raw counts for unique profiles
    my $makeRawCounts = $self->getIsUnique() ? "TRUE" : "FALSE";

    my $findMedian = $self->getFindMedian() ? "TRUE" : "FALSE";
    my $isLogged = $self->getIsLogged() ? "TRUE" : "FALSE";
    my $statistic = $self->getFindMedian() ? "median" : "average";
    $self->addProtocolParamValue("statistic", $statistic);
    $self->addProtocolParamValue("isLogged", $isLogged);

    # begin R string
    my $rString = <<RString;

source("$ENV{GUS_HOME}/lib/R/StudyAssayResults/profile_functions.R");

dat = read.table("$tpmFile", header=T, sep="\\t", check.names=FALSE);

dat.samples = list()
$samples
#------------------------------------------------------------------------

# write out sample TPM values
reorderedSamples = reorderAndGetColCentralVal(pl=dat.samples, df=dat, computeMedian=$findMedian);
write.table(reorderedSamples\$data, file="$outputFile", quote=F, sep="\\t", row.names=reorderedSamples\$id, col.names=NA);

# write out stderrs
if ($makeStandardError) {
    write.table(reorderedSamples\$stdErr, file="$stdErrOutputFile", quote=F, sep="\\t", row.names=reorderedSamples\$id, col.names=NA);
}

# write out percentiles
if ($makePercentiles) {
    reorderedSamples\$percentile = percentileMatrix(m=reorderedSamples\$data);
    write.table(reorderedSamples\$percentile, file="$pctOutputFile", quote=F, sep="\\t", row.names=reorderedSamples\$id, col.names=NA);
}

# now sample Count values
if ($makeRawCounts) {
    dat.count = read.table("$countFile", header=T, sep="\\t", check.names=FALSE);

    #filter out additional rows added by htseq-count
    dat.count = dat.count[!grepl("^__", dat.count\$U_ID),]

    # ensure that the genes are in the same order as the TPM
    dat.count = dat.count[order(match(dat.count\$U_ID, dat\$U_ID)), , drop=FALSE]

    reorderedCounts = reorderAndGetColCentralVal(pl=dat.samples, df=dat.count, computeMedian=$findMedian);
    write.table(reorderedCounts\$data, file="$countOutputFile", quote=F, sep="\\t", row.names=reorderedCounts\$id, col.names=NA);
}


### Here we make individual files
### Header names match results tables

samplesDir = paste(dirname("$outputFile"), "/", ".", basename("$outputFile"), sep="");
dir.create(samplesDir)

for (i in 1:ncol(reorderedSamples\$data)) {
    sampleId = colnames(reorderedSamples\$data)[i];
    # this is the TPM data
    sample = as.matrix(reorderedSamples\$data[,i]);
    colnames(sample) = c("value");

    # add the averaged but otherwise raw count data
    if ($makeRawCounts) {
        countSample = as.matrix(reorderedCounts\$data[,i]);
        colnames(countSample) = c("mean_raw_count");
        sample = cbind(sample, countSample);
    }

    if ($makeStandardError) {
        stdErrSample = as.matrix(reorderedSamples\$stdErr[,i]);
        colnames(stdErrSample) = c("standard_error");
        sample = cbind(sample, stdErrSample);
    }

    if ($makePercentiles) {
        pctSample = as.matrix(reorderedSamples\$percentile[,i]);
        colnames(pctSample) = c("percentile_channel1");
        sample = cbind(sample, pctSample);
    }

    # Fix disallowed characters
    # spaces become underscores,  ( and ) are removed
    sampleFile = gsub(\" \", \"_\", sampleId, fixed=TRUE);
    sampleFile = gsub(\"(\", \"\", sampleFile, fixed=TRUE);
    sampleFile = gsub(\")\", \"\", sampleFile, fixed=TRUE);

    write.table(sample, file=paste(samplesDir, "/", sampleFile, sep=""), quote=F, sep="\\t", row.names=reorderedSamples\$id, col.names=NA);
}

quit("no");
RString

    binmode $rfh, ':encoding(UTF-8)';
    print $rfh $rString;
    close $rfh;


    return $rFile;
}

sub readDataHash {
    my ($self) = @_;
    
    my $mainDirectory = $self->getMainDirectory();
    #make dataHash for TPM values
    chdir "$mainDirectory/TPM";

    my $tpmHash = $self->SUPER::readDataHash();
    $self->{dataHash}->{TPM} = $tpmHash;

    # now the counts
    chdir "$mainDirectory/results";

    # set file suffix for counts files
    my $fileSuffix = $self->getFileSuffix();
    $fileSuffix =~ s/tpm/counts/;
    $self->setFileSuffix($fileSuffix);

    my $countsHash = $self->SUPER::readDataHash();
    $self->{dataHash}->{counts} = $countsHash;

    #must chdir back to mainDirectory when done
    chdir $mainDirectory;
}

sub writeDataHash {
    my ($self, $type) = @_;
 
    my $dataHash;
    if ($type eq "TPM") {
        $dataHash = $self->{dataHash}->{TPM};
    } elsif ($type eq "counts") {
        $dataHash = $self->{dataHash}->{counts};
    }

    my $headers = $self->getHeaders();

    my ($fh, $file) = tempfile();

    print $fh "U_ID\t" . join("\t", @$headers) . "\n";

    foreach my $uid (sort keys %$dataHash) {
        my @values = map {defined($dataHash->{$uid}->{$_}) ? $dataHash->{$uid}->{$_} : 'NA'} @$headers;
        print $fh "$uid\t" . join("\t", @values) . "\n";
    }
    return $file;
}

sub createEDACountsFile {
    my ($self) = @_;

    my $strand = $self->getStrand();
    my $mainDirectory = $self->getMainDirectory();
    my $edaFile = "$mainDirectory/analysis_output/countsForEda_$strand.txt";
    open (EDA, ">$edaFile") or die "Cannot  open $edaFile for writing\n$!\n";

    my $countHash = $self->{dataHash}->{counts};

    # in this context, a "sample" is an individual replicate
    my $samples = $self->getHeaders();

    print EDA "\t";
    print EDA join("\t", @$samples), "\n";
 
    foreach my $gene (keys(%$countHash)) {
        print EDA "$gene\t";
        my $i = 0;
        foreach my $sample (@$samples) {
            my $value = $countHash->{$gene}->{$sample};
            $i ++;
            print EDA "$value";
            if ($i < scalar @$samples) {
                print EDA "\t";
            } else {
                print EDA "\n";
            }
        }
    }
    close EDA
}

sub munge {
    my ($self) = @_;

    my $isUnique = $self->getIsUnique();

    $self->readDataHash();

    my $tpmFile = $self->writeDataHash("TPM");
    $self->setTpmFile($tpmFile);

    # only want to load counts for unique profiles
    my $countFile;
    if ($isUnique) {
        $countFile = $self->writeDataHash("counts");
        $self->setCountFile($countFile);
    }

    $self->SUPER::munge();
    
    unlink($tpmFile);
    if ($isUnique) {
        unlink($countFile);
    }
    
    if ($isUnique) {
        $self->createEDACountsFile();
    }
    
}   


1;
