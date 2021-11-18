
package ApiCommonData::Load::IterativeWGCNAResults;
use base qw(CBIL::TranscriptExpression::DataMunger::Loadable);

use strict;
#use CBIL::TranscriptExpression::Error;
use CBIL::TranscriptExpression::DataMunger::NoSampleConfigurationProfiles;

use Data::Dumper;

use DBI;
use DBD::Oracle;

use GUS::Supported::GusConfig;

sub getStrandness        { $_[0]->{strandness} }
sub getGeneType        { $_[0]->{genetype} }
sub getPower        { $_[0]->{softThresholdPower} }
sub getOrganism        { $_[0]->{organism} }
sub getInputSuffixMM              { $_[0]->{inputSuffixMM} }
sub getInputSuffixME              { $_[0]->{inputSuffixME} }
sub getInputFile              { $_[0]->{inputFile} }
sub getprofileSetName              { $_[0]->{profileSetName} }
sub getTechnologyType              { $_[0]->{technologyType} }
sub getReadsThreshold              { $_[0]->{readsThreshold} }
sub getDatasetName            { $_[0]->{datasetName} }


#-------------------------------------------------------------------------------
sub new {
  my ($class, $args) = @_; 
  $args->{sourceIdType} = "gene";
  my $self = $class->SUPER::new($args) ;          
  
  return $self;
}

#------ Note: two versions of inputs ae used to running iterativeWGCNA method -----------#
#----- version1: only include protein-coding gene in the input tpm file -----------------#
#----- version2: only exclude pseudogenes in the input tpm file -------------------------#

sub munge {
    my ($self) = @_;
    #------------- database configuration -----------#
    my $strandness = $self->getStrandness();
    my $mainDirectory = $self->getMainDirectory();
    my $technologyType = $self->getTechnologyType();
    my $profileSetName = $self->getprofileSetName();
    my $gusconfig = GUS::Supported::GusConfig->new("$ENV{GUS_HOME}/config/gus.config");
    my $dsn = $gusconfig->getDbiDsn();
    my $login = $gusconfig->getDatabaseLogin();
    my $password = $gusconfig->getDatabasePassword();

    my $dbh = DBI->connect($dsn, $login, $password, { PrintError => 1, RaiseError => 0})
	or die "Can't connect to the tracking database: $DBI::errstr\n";
    #--first strand processing ------------------------------------------#
    if($strandness eq 'firststrand'){
	my $power = $self->getPower();
	my $inputFile = $self->getInputFile();
	my $organism = $self->getOrganism();
	my $genetype = $self->getGeneType();
	my $readsThreshold = $self->getReadsThreshold();
	my $datasetName = $self->getDatasetName();
	#--Version1: first strand processing  (only keep protein-coding gene in the input tpm file)-------------#
	if($genetype eq 'protein coding'){
	    my $outputFile = "Preprocessed_proteincoding_" . $inputFile;
	    my $sql = "SELECT source_id 
                   FROM apidbtuning.geneAttributes  
                   WHERE organism = '$organism' AND gene_type = 'protein coding gene'";
	    my $stmt = $dbh->prepare($sql);
	    $stmt->execute();
	    my %hash;
	    
	    while(my ($proteinCodingGenes) = $stmt->fetchrow_array() ) {
				$hash{$proteinCodingGenes} = 1;
	    }
	    
	    $stmt->finish();
	    #-------------- add 1st column header & only keep PROTEIN CODING GENES -----#
	    open(IN, "<", $inputFile) or die "Couldn't open file $inputFile for reading, $!";
	    open(OUT,">$mainDirectory/$outputFile") or die "Couldn't open file $mainDirectory/$outputFile for writing, $!";
	    
	    my %inputs;
	    while (my $line = <IN>){
				$line =~ s/\n//g;
				if ($. == 1){
					my @all = split("\t",$line);
					foreach(@all[1 .. $#all]){
						$inputs{$_} = 1;
					}
				}
			}
	    close IN;
	    
	    open(IN, "<", $inputFile) or die "Couldn't open file $inputFile for reading, $!";
	    while (my $line = <IN>){
				if ($. == 1){
						my @all = split/\t/,$line;
						$all[0] = 'Gene';
						my $new_line = join("\t",@all);
						print OUT $new_line;
						
						foreach(@all[1 .. $#all]){
							@all = grep {s/^\s+|\s+$//g; $_ } @all;
							$inputs{$_} = 1;
						}
				}else{
						my @all = split/\t/,$line;
						if ($hash{$all[0]}){
							print OUT $line;
						}
				}
	    }
	    close IN;
	    close OUT;

	    my $commForPermission = "chmod g+w $outputFile";
	    system($commForPermission);
	    #-------------- run IterativeWGCNA docker image -----#
	    my $comm = "mkdir $mainDirectory/FirstStrandProteinCodingOutputs; chmod g+w $mainDirectory/FirstStrandProteinCodingOutputs";
	    system($comm);
	    my $outputDir = $mainDirectory . "/FirstStrandProteinCodingOutputs";

	    my $inputFileForWGCNA = "$mainDirectory/$outputFile";
	    my $command = "singularity run  docker://jbrestel/iterative-wgcna -i $inputFileForWGCNA  -o  $outputDir  -v  --wgcnaParameters maxBlockSize=3000,networkType=signed,power=$power,minModuleSize=10,reassignThreshold=0,minKMEtoStay=0.8,minCoreKME=0.8  --finalMergeCutHeight 0.25";
	    #my $command = "singularity run --bind $mainDirectory:/home/docker   docker://jbrestel/iterative-wgcna -i /home/docker$outputFile  -o  /home/docker/$outputDir  -v  --wgcnaParameters maxBlockSize=3000,networkType=signed,power=$power,minModuleSize=10,reassignThreshold=0,minKMEtoStay=0.8,minCoreKME=0.8  --finalMergeCutHeight 0.25"; 
	    
	    my $results  =  system($command);
	    
	    #-------------- parse Module Membership -----#
	    my $commgw = "mkdir $mainDirectory/FirstStrandProteinCodingOutputs/FirstStrandMMResultsForLoading; chmod g+w $mainDirectory/FirstStrandProteinCodingOutputs/FirstStrandMMResultsForLoading";
	    system($commgw);
	    my $outputDirModuleMembership = "$mainDirectory/FirstStrandProteinCodingOutputs/FirstStrandMMResultsForLoading/";
	    
	    open(MM, "<", "$outputDir/merged-0.25-membership.txt") or die "Couldn't open $outputDir/merged-0.25-membership.txt for reading";
	    my %MMHash;
	    while (my $line = <MM>) {
				if ($. == 1){
						next;
				}else{
						chomp($line);
						$line =~ s/\r//g;
						my @all = split/\t/,$line;
						push @{$MMHash{$all[1]}}, "$all[0]\t$all[2]\n";
				}
	    }
	    close MM;
	    
	    my @files;
	    my @modules;
	    my @allKeys = keys %MMHash;
	    my @ModuleNames = grep { $_ ne 'UNCLASSIFIED' } @allKeys; 
	    for my $i(@ModuleNames){
				push @modules,$i . " " . $self->getInputSuffixMM() . " " . "ProteinCoding";
				push @files,"$i" . "_1st" . "\.txt" . " " . $self->getInputSuffixMM() . " " . "ProteinCoding" ;
				open(MMOUT, ">$outputDirModuleMembership/$i" . "_1st_ProteinCoding" . "\.txt") or die $!;
				print MMOUT "geneID\tcorrelation_coefficient\n";
				for my $ii(@{$MMHash{$i}}){
						print MMOUT $ii;
				}
				close MMOUT;
	    }
	    my %inputProtocolAppNodesHash;
	    foreach(@modules) {
				push @{$inputProtocolAppNodesHash{$_}}, map { $_ . " " . $self->getInputSuffixMM() } sort keys %inputs;
	    }
	    
	    $self->setInputProtocolAppNodesHash(\%inputProtocolAppNodesHash);
	    $self->setNames(\@modules);                                                                                           
	    $self->setFileNames(\@files);
	    $self->setProtocolName("WGCNA");
	    $self->setSourceIdType("gene");
	    $self->createConfigFile();
	    
	    #-------------- parse Module Eigengene -----#
	    #-- copy module_egene file to one upper dir and the run doTranscription --#
	    my $CPcommand = "cp  $outputDir/merged-0.25-eigengenes.txt  . ; 
                         mv merged-0.25-eigengenes.txt merged-0.25-eigengenes_1stStrand_ProteinCoding.txt ";
	    my $CPresults  =  system($CPcommand);
	    
	    my $egenes = CBIL::TranscriptExpression::DataMunger::NoSampleConfigurationProfiles->new(
		{mainDirectory => "$mainDirectory", inputFile => "merged-0.25-eigengenes_1stStrand_ProteinCoding.txt",makePercentiles => 0,doNotLoad => 0, profileSetName => "$profileSetName"}
		);
	    $egenes ->setTechnologyType("RNASeq");
	    $egenes->setProtocolName("WGCNAME");
	    
	    $egenes ->munge();
	    
	}

	#-- Version2: first strand processing  (only remove pseudogenes in the input tpm file)-------------#
	if($genetype eq 'exclude pseudogene'){
		print "Excluding pseudogenes";
		my $outputFile = "Preprocessed_excludePseudogene_" . $inputFile;
		my $sql = "SELECT ga.source_id,
								ta.length
							FROM apidbtuning.geneAttributes ga,
								apidbtuning.transcriptAttributes ta
							WHERE ga.organism = '$organism'
							AND ga.gene_type != 'pseudogene'
							AND ga.gene_id = ta.gene_id";
		my $stmt = $dbh->prepare($sql);
		$stmt->execute();
		my %hash;
		my %hash_length;
		
		while(my ($proteinCodingGenes, $transcript_length) = $stmt->fetchrow_array() ) {
			$hash{$proteinCodingGenes} = 1;
			$hash_length{$proteinCodingGenes} = $transcript_length;
		}
	    
		$stmt->finish();
		#--- Calculate average unique reads for this dataset ---#
		my ($avg_unique_reads) = $dbh->selectrow_array("select avg(avg_unique_reads)
													from apidbtuning.rnaseqstats
													where dataset_name = '$datasetName'
													group by dataset_name");

		print "Dataset avg unique reads";
		print $avg_unique_reads;

		#-------------- add 1st column header & only keep PROTEIN CODING GENES -----#
		open(IN, "<", $inputFile) or die "Couldn't open file $inputFile for reading, $!";
		open(OUT,">$mainDirectory/$outputFile") or die "Couldn't open file $mainDirectory/$outputFile for writing, $!";
		
		my %inputs;
		while (my $line = <IN>){
			$line =~ s/\n//g;
			if ($. == 1){
					my @all = split("\t",$line);
					print @all;
					foreach(@all[1 .. $#all]){
						$inputs{$_} = 1;
					}
			}
		}
	close IN;
	
	#-- Write lines to wgcna input file and apply floor expression value --#
	open(IN, "<", $inputFile) or die "Couldn't open file $inputFile for reading, $!";
	while (my $line = <IN>){
		if ($. == 1){
			#-- Heading --#
			my @all = split/\t/,$line;
			$all[0] = 'Gene';
			my $new_line = join("\t",@all);
			print OUT $new_line;
			
			foreach(@all[1 .. $#all]){
				@all = grep {s/^\s+|\s+$//g; $_ } @all;
				$inputs{$_} = 1;
			}
		}else{
			#-- Each line describes one gene --#
			my @all = split/\t/,$line;
			print $line;

			#-- Calculate and apply the floor based on the pre-defiend readsThreshold --#
			my $hard_floor = $readsThreshold * 1000000 * $hash_length{$all[0]} / $avg_unique_reads;
			foreach(@all[1 .. $#all]){
				if ($_ < $hard_floor) {
					$_ = $hard_floor;
				}
			}

			$line = join("\t",@all);
			print $line;

			if ($hash{$all[0]}){
			  print OUT $line;
			}
		}
	}
	close IN;
	close OUT;
	    
	#-------------- run IterativeWGCNA docker image -----#
	my $commForPermission = "chmod g+w $outputFile";
	system($commForPermission);
	my $outputDir = $mainDirectory . "/FirstStrandExcludePseudogeneOutputs";

	my $inputFileForWGCNA = "$mainDirectory/$outputFile";
	my $command = "singularity run  docker://jbrestel/iterative-wgcna -i $inputFileForWGCNA  -o  $outputDir  -v  --wgcnaParameters maxBlockSize=3000,networkType=signed,power=$power,minModuleSize=10,reassignThreshold=0,minKMEtoStay=0.8,minCoreKME=0.8  --finalMergeCutHeight 0.25";
	#my $command = "singularity run --bind $mainDirectory:/home/docker   docker://jbrestel/iterative-wgcna -i /home/docker$outputFile  -o  /home/docker/$outputDir  -v  --wgcnaParameters maxBlockSize=3000,networkType=signed,power=$power,minModuleSize=10,reassignThreshold=0,minKMEtoStay=0.8,minCoreKME=0.8  --finalMergeCutHeight 0.25"; 
	
	my $results  =  system($command);
	
	#-------------- parse Module Membership -----#
	my $commgw = "mkdir $mainDirectory/FirstStrandExcludePseudogeneOutputs/FirstStrandMMResultsForLoading; chmod g+w $mainDirectory/FirstStrandExcludePseudogeneOutputs/FirstStrandMMResultsForLoading";
	system($commgw);
	
	my $outputDirModuleMembership = "$mainDirectory/FirstStrandExcludePseudogeneOutputs/FirstStrandMMResultsForLoading/";
	
	open(MM, "<", "$outputDir/merged-0.25-membership.txt") or die "Couldn't open $outputDir/merged-0.25-membership.txt for reading";
	my %MMHash;
	while (my $line = <MM>) {
		if ($. == 1){
		    next;
		}else{
		    chomp($line);
		    $line =~ s/\r//g;
		    my @all = split/\t/,$line;
		    push @{$MMHash{$all[1]}}, "$all[0]\t$all[2]\n";
		}
	    }
	    close MM;
	    
	    my @files;
	    my @modules;
	    my @allKeys = keys %MMHash;
	    my @ModuleNames = grep { $_ ne 'UNCLASSIFIED' } @allKeys; 
	    for my $i(@ModuleNames){
		push @modules,$i . " " . $self->getInputSuffixMM() . " " . "ExcludePseudogene";
		push @files,"$i" . "_1st" . "\.txt" . " " . $self->getInputSuffixMM() . " " . "ExcludePseudogene" ;
		open(MMOUT, ">$outputDirModuleMembership/$i" . "_1st_ExcludePseudogene" . "\.txt") or die $!;
		print MMOUT "geneID\tcorrelation_coefficient\n";
		for my $ii(@{$MMHash{$i}}){
		    print MMOUT $ii;
		}
		close MMOUT;
	    }
	    my %inputProtocolAppNodesHash;
	    foreach(@modules) {
		push @{$inputProtocolAppNodesHash{$_}}, map { $_ . " " . $self->getInputSuffixMM() } sort keys %inputs;
	    }
	    
	    $self->setInputProtocolAppNodesHash(\%inputProtocolAppNodesHash);
	    $self->setNames(\@modules);                                                                                           
	    $self->setFileNames(\@files);
	    $self->setProtocolName("WGCNA");
	    $self->setSourceIdType("gene");
	    $self->createConfigFile();
	    
	    #-------------- parse Module Eigengene -----#
	    #-- copy module_egene file to one upper dir and the run doTranscription --#
	    my $CPcommand = "cp  $outputDir/merged-0.25-eigengenes.txt  . ; 
                         mv merged-0.25-eigengenes.txt merged-0.25-eigengenes_1stStrand_ExcludePseudogene.txt ";
	    my $CPresults  =  system($CPcommand);
	    
	    my $egenes = CBIL::TranscriptExpression::DataMunger::NoSampleConfigurationProfiles->new(
		{mainDirectory => "$mainDirectory", inputFile => "merged-0.25-eigengenes_1stStrand_ExcludePseudogene.txt",makePercentiles => 0,doNotLoad => 0, profileSetName => "$profileSetName"}
		);
	    $egenes ->setTechnologyType("RNASeq");
	    $egenes->setProtocolName("WGCNAME");
	    
	    $egenes ->munge();
	    
	}
    }



   #--second strand processing ------------------------------------------#
    if($strandness eq 'secondstrand'){
	my $power = $self->getPower();
	my $inputFile = $self->getInputFile();
	my $organism = $self->getOrganism();
	my $genetype = $self->getGeneType();
	#--Version1: second strand processing  (only keep protein-coding gene in the input tpm file)-------------#
	if($genetype eq 'protein coding'){
	    my $outputFile = "Preprocessed_proteincoding_" . $inputFile;
	    my $sql = "SELECT source_id 
                   FROM apidbtuning.geneAttributes  
                   WHERE organism = '$organism' AND gene_type = 'protein coding gene'";
	    my $stmt = $dbh->prepare($sql);
	    $stmt->execute();
	    my %hash;
	    
	    while(my ($proteinCodingGenes) = $stmt->fetchrow_array() ) {
		$hash{$proteinCodingGenes} = 1;
	    }
	    
	    $stmt->finish();
	    #-------------- add 1st column header & only keep PROTEIN CODING GENES -----#
	    open(IN, "<", $inputFile) or die "Couldn't open file $inputFile for reading, $!";
	    open(OUT,">$mainDirectory/$outputFile") or die "Couldn't open file $mainDirectory/$outputFile for writing, $!";
	    
	    my %inputs;
	    while (my $line = <IN>){
		$line =~ s/\n//g;
		if ($. == 1){
		    my @all = split("\t",$line);
		    foreach(@all[1 .. $#all]){
			$inputs{$_} = 1;
		    }
		}
	}
	    close IN;
	    
	    open(IN, "<", $inputFile) or die "Couldn't open file $inputFile for reading, $!";
	    while (my $line = <IN>){
		if ($. == 1){
		    my @all = split/\t/,$line;
		    $all[0] = 'Gene';
		    my $new_line = join("\t",@all);
		    print OUT $new_line;
		    
		    foreach(@all[1 .. $#all]){
			@all = grep {s/^\s+|\s+$//g; $_ } @all;
			$inputs{$_} = 1;
		    }
		}else{
		    my @all = split/\t/,$line;
		    if ($hash{$all[0]}){
			print OUT $line;
		    }
		}
	    }
	    close IN;
	    close OUT;

	    my $commForPermission = "chmod g+w $outputFile";
	    system($commForPermission);
	    #-------------- run IterativeWGCNA docker image -----#
	    my $comm = "mkdir $mainDirectory/SecondStrandProteinCodingOutputs; chmod g+w $mainDirectory/SecondStrandProteinCodingOutputs";
	    system($comm);
	    my $outputDir = $mainDirectory . "/SecondStrandProteinCodingOutputs";

	    my $inputFileForWGCNA = "$mainDirectory/$outputFile";
	    my $command = "singularity run  docker://jbrestel/iterative-wgcna -i $inputFileForWGCNA  -o  $outputDir  -v  --wgcnaParameters maxBlockSize=3000,networkType=signed,power=$power,minModuleSize=10,reassignThreshold=0,minKMEtoStay=0.8,minCoreKME=0.8  --finalMergeCutHeight 0.25";
	    #my $command = "singularity run --bind $mainDirectory:/home/docker   docker://jbrestel/iterative-wgcna -i /home/docker$outputFile  -o  /home/docker/$outputDir  -v  --wgcnaParameters maxBlockSize=3000,networkType=signed,power=$power,minModuleSize=10,reassignThreshold=0,minKMEtoStay=0.8,minCoreKME=0.8  --finalMergeCutHeight 0.25"; 
	    
	    my $results  =  system($command);
	    
	    #-------------- parse Module Membership -----#
	    my $commgw = "mkdir $mainDirectory/SecondStrandProteinCodingOutputs/SecondStrandMMResultsForLoading; chmod g+w $mainDirectory/SecondStrandProteinCodingOutputs/SecondStrandMMResultsForLoading/";
	    system($commgw);

	    my $outputDirModuleMembership = "$mainDirectory/SecondStrandProteinCodingOutputs/SecondStrandMMResultsForLoading/";
	    
	    open(MM, "<", "$outputDir/merged-0.25-membership.txt") or die "Couldn't open $outputDir/merged-0.25-membership.txt for reading";
	    my %MMHash;
	    while (my $line = <MM>) {
		if ($. == 1){
		    next;
		}else{
		    chomp($line);
		    $line =~ s/\r//g;
		    my @all = split/\t/,$line;
		    push @{$MMHash{$all[1]}}, "$all[0]\t$all[2]\n";
		}
	    }
	    close MM;
	    
	    my @files;
	    my @modules;
	    my @allKeys = keys %MMHash;
	    my @ModuleNames = grep { $_ ne 'UNCLASSIFIED' } @allKeys; 
	    for my $i(@ModuleNames){
		push @modules,$i . " " . $self->getInputSuffixMM() . " " . "ProteinCoding";
		push @files,"$i" . "_2nd" . "\.txt" . " " . $self->getInputSuffixMM() . " " . "ProteinCoding" ;
		open(MMOUT, ">$outputDirModuleMembership/$i" . "_2nd_ProteinCoding" . "\.txt") or die $!;
		print MMOUT "geneID\tcorrelation_coefficient\n";
		for my $ii(@{$MMHash{$i}}){
		    print MMOUT $ii;
		}
		close MMOUT;
	    }
	    my %inputProtocolAppNodesHash;
	    foreach(@modules) {
		push @{$inputProtocolAppNodesHash{$_}}, map { $_ . " " . $self->getInputSuffixMM() } sort keys %inputs;
	    }
	    
	    $self->setInputProtocolAppNodesHash(\%inputProtocolAppNodesHash);
	    $self->setNames(\@modules);                                                                                           
	    $self->setFileNames(\@files);
	    $self->setProtocolName("WGCNA");
	    $self->setSourceIdType("gene");
	    $self->createConfigFile();
	    
	    #-------------- parse Module Eigengene -----#
	    #-- copy module_egene file to one upper dir and the run doTranscription --#
	    my $CPcommand = "cp  $outputDir/merged-0.25-eigengenes.txt  . ; 
                         mv merged-0.25-eigengenes.txt merged-0.25-eigengenes_2ndStrand_ProteinCoding.txt ";
	    my $CPresults  =  system($CPcommand);
	    
	    my $egenes = CBIL::TranscriptExpression::DataMunger::NoSampleConfigurationProfiles->new(
		{mainDirectory => "$mainDirectory", inputFile => "merged-0.25-eigengenes_2ndStrand_ProteinCoding.txt",makePercentiles => 0,doNotLoad => 0, profileSetName => "$profileSetName"}
		);
	    $egenes ->setTechnologyType("RNASeq");
	    $egenes->setProtocolName("WGCNAME");
	    
	    $egenes ->munge();
	    
	}

	#-- Version2: second strand processing  (only remove pseudogenes in the input tpm file)-------------#
	if($genetype eq 'exclude pseudogene'){
	    my $outputFile = "Preprocessed_excludePseudogene_" . $inputFile;
	    my $sql = "SELECT source_id 
                   FROM apidbtuning.geneAttributes  
                   WHERE organism = '$organism' AND gene_type != 'pseudogene'";
	    my $stmt = $dbh->prepare($sql);
	    $stmt->execute();
	    my %hash;
	    
	    while(my ($proteinCodingGenes) = $stmt->fetchrow_array() ) {
		$hash{$proteinCodingGenes} = 1;
	    }
	    
	    $stmt->finish();
	    #-------------- add 1st column header & only keep PROTEIN CODING GENES -----#
	    open(IN, "<", $inputFile) or die "Couldn't open file $inputFile for reading, $!";
	    open(OUT,">$mainDirectory/$outputFile") or die "Couldn't open file $mainDirectory/$outputFile for writing, $!";
	    
	    my %inputs;
	    while (my $line = <IN>){
		$line =~ s/\n//g;
		if ($. == 1){
		    my @all = split("\t",$line);
		    foreach(@all[1 .. $#all]){
			$inputs{$_} = 1;
		    }
		}
	}
	    close IN;
	    
	    open(IN, "<", $inputFile) or die "Couldn't open file $inputFile for reading, $!";
	    while (my $line = <IN>){
		if ($. == 1){
		    my @all = split/\t/,$line;
		    $all[0] = 'Gene';
		    my $new_line = join("\t",@all);
		    print OUT $new_line;
		    
		    foreach(@all[1 .. $#all]){
			@all = grep {s/^\s+|\s+$//g; $_ } @all;
			$inputs{$_} = 1;
		    }
		}else{
		    my @all = split/\t/,$line;
		    if ($hash{$all[0]}){
			print OUT $line;
		    }
		}
	    }
	    close IN;
	    close OUT;
	    
	    my $commForPermission = "chmod g+w $outputFile";
	    system($commForPermission);
	    #-------------- run IterativeWGCNA docker image -----#
	    my $comm = "mkdir $mainDirectory/SecondStrandExcludePseudogeneOutputs; chmod g+w $mainDirectory/SecondStrandExcludePseudogeneOutputs";
	    system($comm);

	    my $outputDir = $mainDirectory . "/SecondStrandExcludePseudogeneOutputs";

	    my $inputFileForWGCNA = "$mainDirectory/$outputFile";
	    my $command = "singularity run  docker://jbrestel/iterative-wgcna -i $inputFileForWGCNA  -o  $outputDir  -v  --wgcnaParameters maxBlockSize=3000,networkType=signed,power=$power,minModuleSize=10,reassignThreshold=0,minKMEtoStay=0.8,minCoreKME=0.8  --finalMergeCutHeight 0.25";
	    #my $command = "singularity run --bind $mainDirectory:/home/docker   docker://jbrestel/iterative-wgcna -i /home/docker$outputFile  -o  /home/docker/$outputDir  -v  --wgcnaParameters maxBlockSize=3000,networkType=signed,power=$power,minModuleSize=10,reassignThreshold=0,minKMEtoStay=0.8,minCoreKME=0.8  --finalMergeCutHeight 0.25"; 
	    
	    my $results  =  system($command);
	    
	    #-------------- parse Module Membership -----#
	    my $commgw = "mkdir $mainDirectory/SecondStrandExcludePseudogeneOutputs/SecondStrandMMResultsForLoading; chmod g+w $mainDirectory/SecondStrandExcludePseudogeneOutputs/SecondStrandMMResultsForLoading";
	    system($commgw);

	    my $outputDirModuleMembership = "$mainDirectory/SecondStrandExcludePseudogeneOutputs/SecondStrandMMResultsForLoading/";
	    
	    open(MM, "<", "$outputDir/merged-0.25-membership.txt") or die "Couldn't open $outputDir/merged-0.25-membership.txt for reading";
	    my %MMHash;
	    while (my $line = <MM>) {
		if ($. == 1){
		    next;
		}else{
		    chomp($line);
		    $line =~ s/\r//g;
		    my @all = split/\t/,$line;
		    push @{$MMHash{$all[1]}}, "$all[0]\t$all[2]\n";
		}
	    }
	    close MM;
	    
	    my @files;
	    my @modules;
	    my @allKeys = keys %MMHash;
	    my @ModuleNames = grep { $_ ne 'UNCLASSIFIED' } @allKeys; 
	    for my $i(@ModuleNames){
		push @modules,$i . " " . $self->getInputSuffixMM() . " " . "ExcludePseudogene";
		push @files,"$i" . "_2nd" . "\.txt" . " " . $self->getInputSuffixMM() . " " . "ExcludePseudogene" ;
		open(MMOUT, ">$outputDirModuleMembership/$i" . "_2nd_ExcludePseudogene" . "\.txt") or die $!;
		print MMOUT "geneID\tcorrelation_coefficient\n";
		for my $ii(@{$MMHash{$i}}){
		    print MMOUT $ii;
		}
		close MMOUT;
	    }
	    my %inputProtocolAppNodesHash;
	    foreach(@modules) {
		push @{$inputProtocolAppNodesHash{$_}}, map { $_ . " " . $self->getInputSuffixMM() } sort keys %inputs;
	    }
	    
	    $self->setInputProtocolAppNodesHash(\%inputProtocolAppNodesHash);
	    $self->setNames(\@modules);                                                                                           
	    $self->setFileNames(\@files);
	    $self->setProtocolName("WGCNA");
	    $self->setSourceIdType("gene");
	    $self->createConfigFile();
	    
	    #-------------- parse Module Eigengene -----#
	    #-- copy module_egene file to one upper dir and the run doTranscription --#
	    my $CPcommand = "cp  $outputDir/merged-0.25-eigengenes.txt  . ; 
                         mv merged-0.25-eigengenes.txt merged-0.25-eigengenes_2ndStrand_ExcludePseudogene.txt ";
	    my $CPresults  =  system($CPcommand);
	    
	    my $egenes = CBIL::TranscriptExpression::DataMunger::NoSampleConfigurationProfiles->new(
		{mainDirectory => "$mainDirectory", inputFile => "merged-0.25-eigengenes_2ndStrand_ExcludePseudogene.txt",makePercentiles => 0,doNotLoad => 0, profileSetName => "$profileSetName"}
		);
	    $egenes ->setTechnologyType("RNASeq");
	    $egenes->setProtocolName("WGCNAME");
	    
	    $egenes ->munge();
	    
	}
    }
    

}



1;

