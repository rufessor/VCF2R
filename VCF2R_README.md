# VCF2R
Genomic data VCF parser.  Generates files designed to import into R as long data frame for ggplot2 or other analyses.
Copyright 2015 Matthew F. Hockin Ph.D. The University of Utah.  

This program is distributed in the hope that it will be
useful, but it is provided “as is” and without any express
or implied warranties. For details, see the full text of
the license.

VCF2R Requires your input vcf file to be sorted by chromosome and position- aside from that it requires a vcf formatted file.  It has been extensively tested using vcf’s generated from WHAM and FreeBayes on whole genome 20X read data sets from multiple species- we find it extremely useful as an enabling tool for data visualization using R and the ggplot2 package. 

Dependicies- CPAN
Getopt::Long
File::Basename

VCF2R_V1.0.pl is a VCF parser designed with a single purpose in mind, generate a data file that enables immediate import into R as a properly formatted long data frame suitable for faceted ggpolot2 analyses.  VCF2R enables you to specify the exact fields, chromosomes, and even chromosome regions you would like to output.  In order to extend the greatest possible flexibility in structuring output, VCF2R accepts extensive command line options in the form-

--region= {CSL} --chr= {CSL} --field= {VCF Header fields} 
--info= {VCF info subfields} --deparse (flag no value) 
--out= {output file name}

VCF2R learns the header of the input file and thus any INFO or HEADER field may be selected for output by simply including multiple items as a comma separated list (CSL).  

--field=ID,REF,ALT,QUAL,FILTER
By DEFAULT VCF2R generates the CHROM and POS fields- there is no need to specify them on the command line 
e.g. --field=CHROM,POS but also no penalty for doing so.  The following command would output CHROM and POS for every called variant on every chromosome of inputFile.vcf

perl VCF2R_V1.0_pl --out output_File_Name inputFile.vcf
As would this:
perl VCF2R_V1.0_pl --field=CHROM,POS --out outputFileName inputFile.vcf

A basic but complete command to VCF2R- generating a file with CHROM, POS, REF, and QUAL fields for every called variant.

perl VCF2R_V1.0_pl --field=REF,QUAL --out outputFileName inputFile.vcf

Note input file is specified LAST without flag and may be a relative or absolute unix file path.

To restrict this list to contain only those calls found for Chromosome 1 and 12

perl VCF2R_V1.0_pl --field=REF,QUAL --chr=1,12 --out outputFileName inputFile.vcf

To further restrict this to list variants within the bp coordinate regions 1000-4000 bp and 50000-150000 bp on chromosome 1 and include all calls made for chromosome 12 

perl VCF2R_V1.0_pl --field=REF,QUAL --chr=1,12 
--region=1000,4000,50000,150000 --out outputFileName inputFile.vcf

So long as the lists of --chr and --region are in the same order one can specify arbitrary numbers of regions per chromosome by simply separating chromosome region bounds with a single “dash” (-).  Thus, adding to prior a restriction that chr 12 output only between 1000 and 1000000 bp AND include every variant on the Y-

perl VCF2R_V1.0_pl --field=REF,QUAL --chr=1,12,Y 
--region=1000,4000,50000,150000-1000,100000
--out outputFileName inputFile.vcf

Finally, the “INFO” field in vcf files often contains information that might be of interest but otherwise is not conveniently formatted.  VCF2R enables you to include any valid INFO subfield (VCF2R learns these from the input file) through use of the --info command line option.  To include a INFO subfield with the name “AT” and “SVLEN”
 
perl VCF2R_V1.0_pl --field=REF,QUAL --info=AT,SVLEN --out outputFileName inputFile.vcf

In some instances the INFO fields are elaborated at yet another depth, VCF2R will de-parse INFO subfields that are further split using “,” as a field separator.  For example, the WHAM “INFO” field looks like this 

LRT=0;WAF=-nan,1,1;GC=0,1;AT=0.111111,0,0,0,0.888889,0,0.444444,0.888889,0.444444,0.444444,0,0,0,0,0,0,0;SI=1.91371;PU=6;SU=8;CU=2;RD=9;NC=5;MQ=60;MQF=0;SP=sr;BE=12,79619371,8;DI=f;END=.;SVLEN=.

VCF2R will automatically deparse the “AT” field which is 

AT=0.111111,0,0,0,0.888889,0,0.444444,0.888889,0.444444,0.444444,0,0,0,0,0,0,0

Into output that looks like this...

AT1	AT2	AT3	AT4	AT5	AT6	AT7	AT8… 
0.111	0	0	0	0.88	0	0.44	0.88…	

BY ADDING A DEPARSE flag- this option is a bare word and does not accept a value.

perl VCF2R_V1.0_pl --field=REF,QUAL --info=AT,SVLEN 
--deparse --out outputFileName inputFile.vcf

Expanding on the VCF2R ability to output bounded chromosome regions.  VCF2R uses an efficient binary search strategy to quickly find the bp coordinate range specified within --region.  It is NOT necessary to provide bp coordinates that exist in the vcf file.  If you DO provide exact (existing) coordinates VCF2R guarantees that it will find and use data precisely bounded by your provided coordinates.  If any of the coordinates you provide in--region are not called and thus do not exist in the file, VCF2R will find the nearest coordinate to this position, inform you of its bp position as compared to your request and generate output within those bounds.  VCF2R does not guarantee which of the two nearest (high or low) coordinates it will choose- except if you specify coordinates outside of the data limits reducing this to single sided problem (guaranteeing it use the CLOSEST coordinate).

It is likely (but not guaranteed) that given identical approximate input coordinates VCF2R will generate identical output coordinates (e.g. repeating any given input file run)- but this is NOT ENFORCED and we suggest you do NOT rely on this - or at least inspect the output (VCF2R generates verbose output to STDERR) to confirm its doing what you think it is.  If your running it identically twice and looking for a different answer this is the ONLY place that *might* occur- if you can demonstrate this is NOT the case please inform me. 

Finally, VCF2R generates some perhaps useful information and prints this to STDERR dynamically during its run.  Simple inspection of this output will let you know if anything went wrong (e.g. you asked for a invalid field).  If the VCF2R output does not look like you expected, look here it may have told you what went wrong.  It also reports progress, in particular it provides verbose information on the binary serach, informing you each time it completes a chromosome chunk and includes time stamps for processing.  

Finally-finally for those interested in processing speed and memory management.  Testing VCF2R using input vcf files that include ~ 7 million variant calls and that are ~ 3 Gb in size.  VCF2R processes this data set to completion in <5 mins using <2.4 Gb memory on a single core (it is NOT multithreaded).  The output file size for every variant call on all chromosomes using this command

perl VCF2R_V1.pl --field=CHROM,POS,ID,REF,ALT,QUAL --info=DP,AF --out test.out input.vcf 

was 155 MB- the original VCF was 2.9 GB.   

I cannot guarantee memory utilization rates- SV2R hashes chromosome sized data chunks to memory and then internally processes for output- this greatly eases the implementation of chromosome length binning etc- however memory utilization will scale with the largest single chromosome data set on a per POS basis- but is essentially independent of inclusion (or exclusion) of command line arguments.  Said another way, if you have approximately 1/2 million variants called for the largest single chromosome in your data set your memory utilization will be <2.6 Gb- this is quite reasonable.  Memory utilization is however not strictly linear with data size- nor is processing speed.
