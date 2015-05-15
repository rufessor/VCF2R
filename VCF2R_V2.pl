#!/usr/bin/env perl
use strict;
use warnings;
$| = 1;     #Do not buffer output to std error

######Copyright 2015 Matthew F. Hockin Ph.D.
#All rights reserved
#The University of Utah
######mhockin@gmail.com

use Getopt::Long;   
use File::Basename;

###########GLOBALS###########
my %SVbyChr; 
ExecuteScript();

sub ExecuteScript{
    my ($usr_FieldsAry_ref, $usr_InfoAry_ref, $usr_ChrAry_ref, $usr_RegionAry_ref, $usrChr_SegmentsHsh_ref, $deparse, $fileOut) = ParseCommand();
    my $VCF_filePath = shift @ARGV;
    die "VCF data file or file path must bare listed as LAST item on command line for VCF2R\n" unless ($VCF_filePath);
    my ($VCFfile, $dir, $ext) = fileparse($VCF_filePath);
    open (my $VCF_in_FH, '<', $dir.$VCFfile.$ext) or die "Cannot open $VCFfile.$ext using this path $dir\nPlease ensure this is correct\n";
    my ($valid_VCF_fieldsAry_ref, $valid_VCF_infoAry_ref, $lastFile_POS) = LoadHeader($VCF_in_FH);
    my $output_Field_IndxHsh_ref = ParseUserRequest($valid_VCF_fieldsAry_ref, $valid_VCF_infoAry_ref, $usr_FieldsAry_ref, $usr_InfoAry_ref);
    open (my $OUT_file_FH, '>', $fileOut) or die "Cannot create output file $fileOut in current directory- please check permissions\n";
    my $header_Write_test = 0; #flag to detect when file header is written- prevents duplicate headers
    my $time_Start = time;
    my %finished_Chr;
    LINE: while(my @returnVals = LoadData($VCF_in_FH, $lastFile_POS, $usrChr_SegmentsHsh_ref)){
        my ($SVbyChr_Hsh_ref, $chr);
        ($SVbyChr_Hsh_ref, $chr, $lastFile_POS) = @returnVals; 
#debug
#        my $newJunk;
#        for  (0 .. $#{$$SVbyChr_Hsh_ref{$chr}}){
#            my @garbage =@{$$SVbyChr_Hsh_ref{$chr}[$_]->{Info}};#{Summary}
#            my $junkLen = scalar(@garbage);
#            print "$junkLen \n" if ($junkLen != $newJunk);
#            $newJunk = $junkLen;
#        }
#end debug      
        last if (eof $VCF_in_FH == 1 && !$chr);
        my $timeNow = localtime();
        print STDERR "Were done loading Chromosome $chr at $timeNow\n";
        my $aryIndxChr_byRegion_ref = FindChrRegionCoords($usrChr_SegmentsHsh_ref, $chr, $SVbyChr_Hsh_ref);
        my $outputHsh_ref = GenerateOUTPUT($aryIndxChr_byRegion_ref, $output_Field_IndxHsh_ref, $SVbyChr_Hsh_ref);
        undef %$SVbyChr_Hsh_ref;
        my ($write_HeaderAry_ref, $fieldLen);
        ($write_HeaderAry_ref, $fieldLen, $header_Write_test) = Parse_OUTPUT($OUT_file_FH, $outputHsh_ref, $valid_VCF_fieldsAry_ref, 
                                                                             $valid_VCF_infoAry_ref, $deparse, $header_Write_test);
        WriteOUT($OUT_file_FH, $write_HeaderAry_ref, $fieldLen, $outputHsh_ref, $deparse);
        if (eof $VCF_in_FH == 1){
            print STDERR "END OF INPUT FILE REACHED. Perl file position \"tell\" is $lastFile_POS\n";
            my $elapsed = time - $time_Start;
            print STDERR "Total processing time for $VCFfile was $elapsed seconds!\n"; 
            last;
        }
        if (%$usrChr_SegmentsHsh_ref){
            my $done = 0;
            $finished_Chr{$chr} = '';
            for (keys %$usrChr_SegmentsHsh_ref){
                $done++ unless (exists $finished_Chr{$_});    
            }
            if ($done == 0){
                print STDERR "finishing file early, we found all requested Chr\n";
                my $elapsed = time - $time_Start;
                print STDERR "Total processing time for $VCFfile was $elapsed seconds!\n";
                last;
            }
        }
    }
    close $VCF_in_FH;
    close $OUT_file_FH; 
    return;
}

sub ParseCommand{
    my ($pullFields, $pullInfo, $pullChrs, $pullRegions, $fileOut, $deparse);
    GetOptions('field=s', => \$pullFields,
                'info=s', => \$pullInfo,       
                'chr=s', => \$pullChrs,        
                'region=s' => \$pullRegions,  
                'out=s' => \$fileOut,
                'deparse' => \$deparse);    
    my @Fields = split(/,/ , uc $pullFields) if $pullFields;
    my @Info = split(/,/ , uc $pullInfo) if $pullInfo;
    my @Chrs;
    if ($pullChrs =~ m/-/){ 
        $pullChrs =~ /\A(\d+)-(\d+)/;
        @Chrs = ($1 .. $2);
        if ($pullChrs =~ m/,/){
         $pullChrs =~ m/\A\d+-\d+,(.+)/;
         my @listedChr = split (/,/ , $1);
         push @Chrs, @listedChr;
        }
    }else{
        @Chrs = split(/,/ , $pullChrs) if $pullChrs;
    }
    my @Regions = split(/-/ , $pullRegions) if $pullRegions;
    my %usrChr_Segments; #container for chr and region information
    if (@Chrs){
        for (0..$#Chrs) {
            my $region_Coords = $Regions[$_] ||= 0;
            push @{$usrChr_Segments{$Chrs[$_]}}, $region_Coords;
        }
    }
    return(\@Fields, \@Info, \@Chrs, \@Regions, \%usrChr_Segments, $deparse, $fileOut);
}

sub LoadHeader{
    my $VCF_file = shift;
    my ($lastFile_POS, @infoHeader, @fieldsHeader);
    LINE: while (my $line = <$VCF_file>){
	next LINE if ($line =~ m/^#{2}/);
        if ($line =~ m/^#{1}/){
            chomp $line;
            $line =~ s/#//;
            push @fieldsHeader, split (/\t/, $line); #record field identifiers from VCF global header
            $lastFile_POS= tell($VCF_file);
            next LINE;
        }
        my @currentLine = split (/\t/, $line);
        my @infoData = split (/;/, $currentLine[7]);
        foreach (@infoData){ 
            $_ =~ m/([a-zA-Z0-9]+)=/g;
            push @infoHeader, $1;
        }
        return(\@fieldsHeader, \@infoHeader, $lastFile_POS);
    }
}

sub LoadData{
    my ($VCF_file, $lastFile_POS, $usrChr_SegmentsHsh_ref) = @_;
    my (%singleLoci, %SVbyChr, @fieldsHeader, @infoHeader, $chr, $chr_Regex, $enable_RegEx_Fail);
	seek($VCF_file, $lastFile_POS, 0);
    LINE: while (my $line =  <$VCF_file>){
        chomp $line;
        my @currentLine = split (/\t/ , $line);
        if (%$usrChr_SegmentsHsh_ref){
            unless (exists $$usrChr_SegmentsHsh_ref{$currentLine[0]}){
                next LINE unless ($enable_RegEx_Fail)
                }
        }
        $enable_RegEx_Fail = 1 unless ($enable_RegEx_Fail);
        $chr = $currentLine[0] unless ($chr);
        $chr_Regex = qr/\A$currentLine[0]\z/i unless ($chr_Regex);
        $currentLine[0] =~ m/$chr_Regex/ ? $lastFile_POS = tell($VCF_file) : return(\%SVbyChr, $chr, $lastFile_POS); 
        my @infoData = split (/;/ , $currentLine[7]);
        s/[a-zA-Z0-9]+=//g for @infoData; #remove header from info fields retain data
        $currentLine[7] = '';  #null value saves hash memory- actual values retained under diff hash key- DO NOT DELETE index pos will be wrong later
        if (exists $singleLoci{$currentLine[0]}{$currentLine[1]}){ #warn of variant calls at redundant Chr, Pos (should not exist)
            warn "Chr $currentLine[0] at $currentLine[1] has previously been called- and will NOT be RECORDED!\nThe consensus seq record for this variant is $currentLine[3]\n";
            $lastFile_POS = tell($VCF_file);
            next LINE;
        }
        my $pos = $currentLine[1]; 
        $singleLoci{$chr}{$pos} = ''; #record in local (temporary) hash to check for redundant chr and pos fields
        my %posInfo; 
        $posInfo{Summary} = \@currentLine;
        $posInfo{Info} = \@infoData;
        $posInfo{POS} = $pos;
        push @{$SVbyChr{$chr}}, \%posInfo; 
    }
    return(\%SVbyChr, $chr, $lastFile_POS);
}

sub ParseUserRequest{
    my ($valid_VCF_FieldsAry_ref, $valid_VCF_InfoAry_ref, $usr_FieldsAry_ref, $usr_InfoAry_ref) = @_;
    my %validQuery;
    my %summary_keys = map {$valid_VCF_FieldsAry_ref->[$_] => $_} (0 .. $#$valid_VCF_FieldsAry_ref);
    my %info_keys = map {$valid_VCF_InfoAry_ref->[$_] => $_} (0 .. $#$valid_VCF_InfoAry_ref);
    my @usr_PullRequests = (@$usr_FieldsAry_ref, @$usr_InfoAry_ref);
    foreach (my $i = 0; $i < @usr_PullRequests; $i++){
        unless (exists $summary_keys{$usr_PullRequests[$i]} || exists $info_keys{$usr_PullRequests[$i]}){
            die "Command line option \"--$usr_PullRequests[$i]\" is not valid VCF field to query.\nPlease check VCF file header and INFO field for other valid queries\n\n";
        }
    }
    for (@$usr_FieldsAry_ref){
        $validQuery{Summary}{$_} = $summary_keys{$_};
    } 
    for (@$usr_InfoAry_ref){
        $validQuery{Info}{$_} = $info_keys{$_};
    }
    delete $validQuery{Summary}{CHROM};  #default output Fields-remove to silently prevent user inadvertently invoking redundant output (see line 92)
    delete $validQuery{Summary}{POS};
    return (\%validQuery);
}

sub FindChrRegionCoords{ #Feeds BinarySearch to determine array bounds of given bp coordinates
    my ($usrChrSegments_Hsh_ref, $chr, $SVbyChr_Hsh_ref) = @_;
    my @indxChr_Regions;
    if (%$usrChrSegments_Hsh_ref){
        my @coordinates_ThisChr = split (/,/ ,  $$usrChrSegments_Hsh_ref{$chr}->[0])  unless ($$usrChrSegments_Hsh_ref{$chr}->[0] == 0);
        if (@coordinates_ThisChr){
            die "Unbounded chr Regions found! REQUIRE \"--region start,end\" coordinate PAIRS on command line!\n" if(@coordinates_ThisChr %2 !=0);
            for (my $i = 0; $i < $#coordinates_ThisChr; $i = $i+2){
                my ($bpStart, $bpEnd) = @coordinates_ThisChr[$i, $i+1];
                my $return_Ary_ref = BinarySearchChrPOS($chr, $bpStart, $bpEnd, $SVbyChr_Hsh_ref);
                unshift @$return_Ary_ref, $chr;
                push @indxChr_Regions, $return_Ary_ref;
            }
        }else{
            my ($region_Start, $region_End) = (0 , $#{$$SVbyChr_Hsh_ref{$chr}}); 
            push @indxChr_Regions, [$chr, $region_Start, $region_End];
        }
    }else{
        my ($region_Start, $region_End) = (0 , $#{$$SVbyChr_Hsh_ref{$chr}}); 
        push @indxChr_Regions, [$chr, $region_Start, $region_End];
    }
    return(\@indxChr_Regions); 
}

sub BinarySearchChrPOS{
    my ($chr, $start, $end, $SVbyChr_Hsh_ref) = @_;
    my @realCoordRange = ($$SVbyChr_Hsh_ref{$chr}[0]->{POS}, $$SVbyChr_Hsh_ref{$chr}[$#{$$SVbyChr_Hsh_ref{$chr}}]->{POS});    
    if ($start < $realCoordRange[0]){
        print STDERR "Requested start position $start on $chr is lower than any called bp position for this Chromosome, using the first called position $realCoordRange[0] instead!\n";
        $start = $realCoordRange[0];
    }elsif ($start > $realCoordRange[1]){
        die "Requested start position $start on $chr is higher than any called bp position for this Chromosome! INVALID coordinate RANGE on --region!\n"; 
    }
    if ($end >$realCoordRange[1]){
        print STDERR "Requested start position $end on $chr is higher than any called bp position for this Chromosome, using the last called position $realCoordRange[1] instead!\n";
        $end = $realCoordRange[1]
    }elsif ($end < $realCoordRange[0]){
        die "Requested end position $end on $chr is lower than any called bp position for this Chromosome! INVALID coordinate RANGE on --region!\n"; 
    }
    my @bpCoordRange = ($start, $end);
    my $foundIndex; #used as ref for array
    foreach my $coord (@bpCoordRange){
        my $maxIndex =  $#{$$SVbyChr_Hsh_ref{$chr}};    #whats the last array entry (highest BP coordinate) for current Chr data set.
        my $stepSize = my $currentIndex = int($maxIndex * 0.5); #start in middle
        push @$foundIndex,  Binary_algorithim($chr, $coord, $stepSize, $currentIndex, $maxIndex, $SVbyChr_Hsh_ref);    
    }
    return $foundIndex;
}

sub Binary_algorithim{
    my ($chr, $coord, $stepSize, $currentIndex, $maxIndex, $SVbyChr_Hsh_ref) = @_;
    my $counter = 0;
    LINE: while ($coord != $$SVbyChr_Hsh_ref{$chr}[$currentIndex]->{POS}){
        while ($coord < $$SVbyChr_Hsh_ref{$chr}[$currentIndex]->{POS}){
            $stepSize = int(0.5 * $stepSize);
            $stepSize == 0 ? $stepSize = 1: $stepSize = $stepSize;
            $currentIndex = $currentIndex - $stepSize; 
            print STDERR "binary search on Chr $chr looking for bp POS $coord.  At index position $currentIndex\ with bp coord $$SVbyChr_Hsh_ref{$chr}[$currentIndex]->{POS}\n";
        }
        while ($coord > $$SVbyChr_Hsh_ref{$chr}[$currentIndex]->{POS}){
            $stepSize = int(0.5 * $stepSize);
            $stepSize == 0 ? $stepSize = 1: $stepSize = $stepSize;
            $currentIndex = $currentIndex + $stepSize;
            print STDERR "binary search on Chr $chr looking for bp POS $coord at index position $currentIndex\ with bp coord $$SVbyChr_Hsh_ref{$chr}[$currentIndex]->{POS}\n";
        }
        $counter ++ if ($stepSize == 1);
        if ($counter >=5){
            warn "We could not find any variant calls for bp $coord on chromosome $chr- despite $counter attempts at local search.\nUsing variant called at bp $$SVbyChr_Hsh_ref{$chr}[$currentIndex]->{POS} on $chr instead!!!!!\n";
            print STDERR "Search complete.\n\n";
            return $currentIndex;
        }
        if ($coord < $$SVbyChr_Hsh_ref{$chr}[$currentIndex]->{POS} ){
            $stepSize = int(0.5 * $stepSize);
            $stepSize == 0 ? $stepSize = 1: $stepSize = $stepSize;
            $currentIndex = $currentIndex - $stepSize;
            print STDERR "binary search reseeded on Chr $chr looking for bp POS $coord at index position $currentIndex\ with bp coord $$SVbyChr_Hsh_ref{$chr}[$currentIndex]->{POS}\n";
            next LINE;
        }
    }
    print STDERR "Search complete.\n\n";
    return $currentIndex;
}


sub GenerateOUTPUT{
    my ($ary_IndxChr_byRegion_ref, $output_Field_IndxHsh_ref, $SVbyChr_Hsh_ref) = @_;
    my %output;
    if (@$ary_IndxChr_byRegion_ref){
        for my $i (0 .. $#$ary_IndxChr_byRegion_ref){
            my ($chr, $regionStart, $regionEnd) = @{$ary_IndxChr_byRegion_ref->[$i]}[0..2];
            for my $coordPos ($regionStart .. $regionEnd){
                push @{$output{CHROM}} , $chr;
                push @{$output{POS}} , ${$$SVbyChr_Hsh_ref{$chr}}[$coordPos]->{POS};
                for my $fieldType (keys %$output_Field_IndxHsh_ref){
                    while (my ($outputField_name, $outputField_index) = each %{$output_Field_IndxHsh_ref->{$fieldType}}){
                        push @{$output{$outputField_name}} , ${$$SVbyChr_Hsh_ref{$chr}}[$coordPos]->{$fieldType}[$outputField_index];
                    }
                }
            }
        }
    }
    else{
        my @chrAry;
        push @chrAry, keys %SVbyChr;
        for my $chr (@chrAry){
            my ($start, $end) = (0, $#{$$SVbyChr_Hsh_ref{$chr}});  #grab ary index coords for entire chromosome
            for my $coordPos ($start .. $end){
                push @{$output{CHROM}} , $chr;
                push @{$output{POS}} , ${$$SVbyChr_Hsh_ref{$chr}}[$coordPos]->{POS};
                for my $fieldType (keys %$output_Field_IndxHsh_ref){
                    while (my ($outputField_name, $outputField_index) = each %{$output_Field_IndxHsh_ref->{$fieldType}}){
                        push @{$output{$outputField_name}} , ${$$SVbyChr_Hsh_ref{$chr}}[$coordPos]->{$fieldType}[$outputField_index];
                    }
                }
            }
        }
    }
    return(\%output);
}

sub Parse_OUTPUT{
    my ($outFile, $outputHsh_ref, $valid_VCF_fieldsAry_ref, $valid_VCF_infoAry_ref, $deparse, $header_EXISTS) = @_;
    my @fields_VCF = @$valid_VCF_fieldsAry_ref;
    my @info_VCF = @$valid_VCF_infoAry_ref;
    my $index = 0;
    for (@fields_VCF){  #splice info header out replace with selected user info sub fields
        if ($_ =~ m/\AINFO\Z/i){
            splice (@fields_VCF, $index, 1);
            splice (@fields_VCF, $index, 0, @info_VCF);
        }
        $index++;
    }
    #check ouputHsh_ref for data consistency prior to parsing header to include subfield indicies
    CheckFieldLen(\@fields_VCF, $outputHsh_ref);
    my $fieldLen = CheckFieldLen(\@info_VCF, $outputHsh_ref);
    my (@write_Header, @header); #begin parsing header-- find fields that need to be expanded- include suffix for internal field #
    LINE: for my $field (@fields_VCF){
        if ($field eq "CHROM" || $field eq "POS"){
            push @header, $field;
            next LINE;
        }
        if (exists $$outputHsh_ref{$field}){
            if ($deparse) {
                if (${$outputHsh_ref}{$field}[0] =~ m/[,]/g){  #does field need to be expanded
                    my @expanded_Field = split (/,/ , ${$outputHsh_ref}{$field}[0]); #get all entries for this data field  
                    my @expanded_Header;
                    for my $number_Suffix(1 .. @expanded_Field){
                        push @expanded_Header, ($field . $number_Suffix);
                    }
                    push @header, @expanded_Header;
                    push @write_Header, $field;
                }else { 
                    push @header, $field;
                    push @write_Header, $field;
                }
            }else{
                push @header, $field;
                push @write_Header, $field;
            }   
        }
    }
    my $ chr = $$outputHsh_ref{CHROM}[0];
    print STDERR "Generating $fieldLen lines for output on Chromosome $chr with the selected fields\n@header\n";
    if ($header_EXISTS == 0){
        print $outFile join ("\t", @header) .  "\n"; #full VCF ordered header for all output Fields see 232
        $header_EXISTS++;
    }
    return (\@write_Header, $fieldLen, $header_EXISTS)
}

sub CheckFieldLen{
    my ($fieldType_Ary_ref, $outputHsh_ref) = @_ ;
    my $counter = 0;
    my ($fieldLen, $priorLen);
    for (@$fieldType_Ary_ref){  #confirm identical output lengths or die due to corrupt data ouput 
        if (exists $$outputHsh_ref{$_}){
            $fieldLen = $#{$$outputHsh_ref{$_}};
            $priorLen = $fieldLen if ($counter == 0);
            $counter++;
        }
        if ($counter > 0){
            die "INTERNAL ERROR uneven array lengths in a data field contained within this lise\n@$fieldType_Ary_ref\n MAIN:sub:WriteOutputFile.\n" if ($priorLen != $fieldLen);
            $priorLen = $fieldLen;
        }
    }
    return $fieldLen;
}

sub WriteOUT{
    my ($outFile, $write_HeaderAry_ref, $fieldLen, $outputHsh_ref, $deparse) = @_;
    my ($count, $priorLineLength);
    for my $line_Num (0 .. $fieldLen){
        my @line; #container for ouput per line
        push @line , ${$outputHsh_ref}{CHROM}[$line_Num];
        push @line , ${$outputHsh_ref}{POS}[$line_Num];
        for my $usr_Field(@$write_HeaderAry_ref){
            my $parse_Line = ${$outputHsh_ref}{$usr_Field}[$line_Num];
            if ($deparse){
                if ($parse_Line =~ m/[,]/g){
                    my @parsed_Line = split (/,/ , $parse_Line);
                    push @line, @parsed_Line;
                } 
                else{
                    push @line , $parse_Line;
                }
            }
            else{
                push @line, $parse_Line;
            }
        }
        my $lineLength = @line;
        unless ($count){
            $priorLineLength = $lineLength;
            $count = 1;
            print STDERR "Tracking output field lengths for consistency\n";
        }else{
            print STDERR "WARN-output field lengths inconsistent!\nLast $priorLineLength\tCurrent $lineLength\n" if ($priorLineLength != $lineLength);
            print STDERR "Current Line is\n @line\n" if ($priorLineLength != $lineLength);
            $priorLineLength = $lineLength;
        }
        for (0 .. $#line){
           $line[$_] = "." if ($line[$_] eq ""); 
        }
        print $outFile join ("\t", @line) . "\n";
    }
    print STDERR "File write succesful for chromosome block\n\n";
    return;
}

