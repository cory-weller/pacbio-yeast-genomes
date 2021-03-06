import pandas as pd
#samples = pd.read_table("samples.tsv").set_index("sample", drop=False)
configfile: "config.yaml"
STRAINS = config['strains']
CROSS = config['cross']

# SAMPLES = list(samples['sample'])   # SAMPLES: list of samples of given BATCH that will be processed
# BATCH = config['run']['batch']      # BATCH: identifies the group of samples we're concerned with, e.g. date of sequencing run
# GENES = list(config['amplicons'].keys())

# format wells as two digits, e.g. leading 0 if 1-9
WELLS = ['0' + str(x) if len(str(x))==1 else str(x) for x in range(1,97)]
PLATES = ['G' + str(x) for x in range(1,6)] + ['R' + str(x) for x in range(1,6)] 
CHROMOSOMES=['IV']

# rule targets identifies the list of final output files to generate
rule targets:
    """Defines the set of files desired at end of pipeline"""
    input: expand("data/vcf/chr{chromosome}/{cross}_{plate}_{well}_chr{chromosome}.vcf", cross=CROSS, plate=PLATES, well=WELLS, chromosome=CHROMOSOMES)



# rule make_blast_db:
#     input: 
#         expand("data/pacbio/pacbio_{strain}.fasta", strain = STRAINS)
#     output: 
#         "data/pacbio/pacbio_db.fasta"
#     threads: 1
#     resources:
#         mem_mb = 1024*2,
#         runtime_min = 5,
#     shell:
#         """
#         cat {input}> {output}
#         ./blast/bin/makeblastdb \
#             -dbtype nucl \
#             -in {output}
#         """

rule split_fastas:
    input:  expand('data/pacbio/pacbio_{strain}.fasta', strain=STRAINS[0]),
            expand('data/pacbio/pacbio_{strain}.fasta', strain=STRAINS[0],)
    output: 'data/pacbio/{strain}_chrIV.fasta'
    threads: 1
    resources:
        mem_mb = 1024*2,
        runtime_min = 5
    shell:
        """
        cd data/pacbio
        awk -F "(^>|\t| )" '{if($0 ~ /^>/) {s=$2".fasta";  print ">"$2 > s} else print > s}' {input}
        """
        
rule run_mummer:
    input:  
        strain1='data/pacbio/273614_chr{chromosome}.fasta',
        strain2='data/pacbio/YJM981_chr{chromosome}.fasta'
    output: 'data/mummer/chr{chromosome}.delta', 'data/mummer/chr{chromosome}.snps'
    threads: 1
    resources:
        mem_mb = 1024*2,
        runtime_min = 5
    shell:
        """
        module load mummer
        infasta1=$(realpath {input.strain1})
        infasta2=$(realpath {input.strain2})
        mkdir -p data/mummer
        cd data/mummer
        nucmer -p chr{wildcards.chromosome} ${{infasta1}} ${{infasta2}} 
        dnadiff -p chr{wildcards.chromosome} -d chr{wildcards.chromosome}.delta
        """

rule print_filter_bed:
    input:  'data/mummer/chr{chromosome}.snps'
    output: 'data/mummer/273614_chr{chromosome}.mask.filter.bed'
    threads: 1
    resources:
        mem_mb = 1024*2,
        runtime_min = 5
    shell:
        """
        src/filter_snps.py {input} 20 > {output}
        """

rule print_vcf_targets:
    input:  'data/mummer/chr{chromosome}.snps'
    output: 'data/mummer/273614_chr{chromosome}.targets.txt'
    threads: 1
    resources:
        mem_mb = 1024*2,
        runtime_min = 5
    params:
        filter_dist = 20
    shell:
        """
        src/print_target_snps.py {input} {params.filter_dist} > {output}
        """


rule mask_fasta:
    input: 
        fasta = 'data/pacbio/273614_chr{chromosome}.fasta',
        bed = 'data/mummer/273614_chr{chromosome}.mask.filter.bed'
    output:
        fasta = 'data/mummer/273614_chr{chromosome}.mask.fasta'
    threads: 1
    resources:
        mem_mb = 1024*2,
        runtime_min = 5
    shell:
        """
        src/mask_fasta.py {input.fasta} {input.bed}  --out {output.fasta}
        """

rule index_masked_fasta:
    input: 'data/mummer/273614_chr{chromosome}.mask.fasta'
    output: 'data/mummer/273614_chr{chromosome}.mask.fasta.bwt'
    threads: 1
    resources:
        mem_mb = 1024*4,
        runtime_min = 5
    container: "library://wellerca/pseudodiploidy/mapping:latest"
    shell:
        """
        bwa index {input}
        """

# # PLOT
# library(data.table)
# library(ggplot2)
# dat <- fread(paste0('data/vcf/', sample, '.vcf'), skip="#CHROM")
# setnames(dat, c('CHROM','POS',' ID','REF','ALT','QUAL','FILTER','INFO','FORMAT','GT'))
# windowSize <- 2000
# dat[, bin := cut(POS, breaks=seq(0,windowSize+max(dat$POS), windowSize))]
# dat[, bin := as.numeric(factor(bin))]
# ggplot(data=dat[, list(POS, fractionAlt = sum(GT==1)/.N), by=bin][fractionAlt > 0.95 | fractionAlt < 0.05], aes(x=POS, y=fractionAlt)) + geom_point()

# rule convert_sam_to_fasta:
#     input: "data/3003.sam.zip"
#     output: temp("data/fasta/{cross}_{plate}_{well}.fasta")
#     threads: 1
#     resources:
#         mem_mb = 1024*2,
#         runtime_min = 20,
#     container: "library://wellerca/pseudodiploidy/mapping:latest"
#     priority: 2
#     shell:
#         """
#         samtools fasta \
#         -1 data/fasta/{wildcards.cross}_{wildcards.plate}_{wildcards.well}.fasta \
#         -2 data/fasta/{wildcards.cross}_{wildcards.plate}_{wildcards.well}.fasta \
#         -0 data/fasta/{wildcards.cross}_{wildcards.plate}_{wildcards.well}.fasta \
#         -s data/fasta/{wildcards.cross}_{wildcards.plate}_{wildcards.well}.fasta \
#         <(cat data/header-{wildcards.cross}.txt <(unzip -p  {input} {wildcards.cross}_{wildcards.plate}_{wildcards.well}.sam))
#         """

# rule run_blastn:
#     input: blast_db = "data/pacbio/pacbio_db.fasta"
#     output: touch("data/blasts/.done")
#     threads: 8
#     resources:
#         mem_mb = 1024*8,
#         runtime_min = 120,
#     params:
#         pct_identity = lambda wildcards: config["pct_identity"],
#         e_value_cutoff = lambda wildcards: config["e_value_cutoff"],
#         cross = lambda wildcards: config["cross"]
#     priority: 3
#     container: "library://wellerca/pseudodiploidy/mapping:latest"
#     shell:
#         """
#         src/convert_sam_to_fasta.sh  data/{params.cross}.sam.zip {params.pct_identity} {threads} {params.e_value_cutoff} {input.blast_db}
#         """

rule convert_fastq:
    input:
        zipfile = "data/{cross}.sam.zip",
        header = 'data/header-3003.txt'
    output: temporary('data/fastq/{cross}_{plate}_{well}.fastq')
    threads: 1
    resources:
        mem_mb = 1024*2,
        runtime_min = 5,
    container: "library://wellerca/pseudodiploidy/mapping:latest"
    shell:
        """
        samtools fastq \
        -1 {output} \
        -2 {output} \
        -0 {output} \
        -s {output} \
        <(cat {input.header} <(unzip -p  {input.zipfile} {wildcards.cross}_{wildcards.plate}_{wildcards.well}.sam))
        """


rule bwa_map:
    input: 
        sample_fastq='data/fastq/{cross}_{plate}_{well}.fastq',
        ref_fasta='data/mummer/273614_chr{chromosome}.mask.fasta',
        indexed_ref='data/mummer/273614_chr{chromosome}.mask.fasta.bwt'
    output: 
        bam='data/bam/{cross}_{plate}_{well}_chr{chromosome}.bam',
        bai='data/bam/{cross}_{plate}_{well}_chr{chromosome}.bam.bai'
    threads: 4
    resources:
        mem_mb = 1024*4,
        runtime_min = 10,
    container: "library://wellerca/pseudodiploidy/mapping:latest"

    shell:
        """
        bwa mem {input.ref_fasta} {input.sample_fastq} | \
        samtools view -hb - | \
        samtools sort - > {output.bam}
        samtools index {output.bam}
        """

rule mpileup:
    input:
        targets='data/mummer/273614_chr{chromosome}.targets.txt',
        bam = 'data/bam/{cross}_{plate}_{well}_chr{chromosome}.bam',
        bai = 'data/bam/{cross}_{plate}_{well}_chr{chromosome}.bam.bai'
    output: 
        vcf='data/vcf/chr{chromosome}/{cross}_{plate}_{well}_chr{chromosome}.vcf'
    threads: 4
    resources:
        mem_mb = 1024*4,
        runtime_min = 5,
    shell:
        """
        module load samtools
        bcftools mpileup \
            --targets-file {input.targets} \
            --fasta-ref 'data/mummer/273614_chr{wildcards.chromosome}.mask.fasta' \
            {input.bam} | \
            bcftools call \
            --ploidy 1 -m -Ob | \
            bcftools view | \
            sed 's/1:.*$/1/g' | \
            grep -v "^##" > {output.vcf}
        """


# src/bwa_map.sh 3003_G1_01.fastq 273614.mask
# src/bwa_map.sh 3003_G1_02.fastq 273614.mask



# bcftools mpileup \
#     --targets-file data/pacbio/273614.targets.txt \
#     --fasta-ref data/pacbio/273614.mask.fasta \
#     data/bam/3003_G1_01_273614.mask.bam | \
#     bcftools call \
#     --ploidy 1 -m -Ob | \
#     bcftools view | \
#     sed 's/1:.*$/1/g' | \
#     grep -v "^##" > test.vcf

# samtools depth data/bam/3003_G1_01_273614.mask.bam

# make bed file


# rule impute_haplotypes:
#     input: "data/blasts/.done"
#     output: touch("data/imputed/.done")
#     threads: 1
#     resources:
#         mem_mb = 1024*2,
#         runtime_min = 5,
#     params:
#         parent1 = STRAINS[0]
#         parent2 = STRAINS[1]
#     priority: 4
#     shell:
#         """
#         module load R/3.6.3
#         Rscript src/linkage_mapping.R {params.parent1} {params.parent2}
#         """
