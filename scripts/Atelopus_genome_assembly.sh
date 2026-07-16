#!/bin/bash
#SBATCH --job-name=Atelopus_genome_assembly
#SBATCH -p long
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=32
#SBATCH --mem=128000
#SBATCH --time=10-05:00:00
#SBATCH --mail-user=v.nascimento@uniandes.edu.co
#SBATCH --mail-type=ALL
#SBATCH -o Atelopus_assembly_%j.out
#SBATCH -e Atelopus_assembly_%j.err


################### modules

module load anaconda/conda4.12.0
module load hifiasm/0.16.1
module load quast/5.0.2
module load busco/5.7.1
module load samtools/1.16.1 

################### conda environment

ENV_NAME=genome_asm

if ! conda env list | grep -q "$ENV_NAME"; then
  conda create -n $ENV_NAME -y -c conda-forge -c bioconda ipa falcon
fi

conda activate $ENV_NAME

################### variables 

THREADS=32
LINEAGE=vertebrata_odb10

# 6 BAM files
BAM_FILES=(A_laetissimus_hifi1.bam A_laetissimus_hifi2.bam A_laetissimus_hifi3.bam A_laetissimus_hifi4.bam A_laetissimus_hifi5.bam A_laetissimus_hifi6.bam)

################### bam to fastq and merge

for bam in "${BAM_FILES[@]}"; do
  samtools fastq -@ $THREADS -0 - "$bam" > "${bam%.bam}.fastq" &
done
wait

cat *.fastq > combined_A_laetissimus_hifi.fastq

################### cutadapt

cutadapt \
  -g AAAAAAAAAAAAAAAAAATTAACGGAGGAGGAGGA \
  -e 0.1 -O 20 \
  -o combinedA_laetissimus_hifi_trimmed.fastq.gz \
  combined_A_laetissimus_hifi.fastq

TRIMMED=combinedA_laetissimus_hifi_trimmed.fastq.gz

################### genome assembly

##### IPA
ipa local --nthreads $THREADS -i $TRIMMED --run-dir ipa_Alaetissimus

##### hifiasm
hifiasm -o hifiasm_Sample_X -t $THREADS -l0 $TRIMMED
awk '/^S/{print ">"$2"\n"$3}' hifiasm_Sample_X.bp.p_ctg.gfa > hifiasm_Sample_X.p_ctg.fasta

##### Falcon
#You'll need to create the running file (cfg file) and the input (fofn file).

cat > fc_run_Atelopus_laetissumus.cfg << EOF
[General]
job_type = local
input_fofn = input.fofn
target = assembly
genome_size = 3500000000

length_cutoff = 12000
length_cutoff_pr = 8000

[General]
skip_checks = True

[Assembly]
overlap_filtering_setting = --max_diff 500 --max_cov 100
EOF

echo "combinedA_laetissimus_hifi_trimmed.fastq.gz" > input.fofn

fc_run fc_run_Atelopus_laetissimus.cfg


################### paths

IPA_ASM=ipa_Alaetittimus/assembly-results/final.p_ctg.fasta
FALCON_ASM=falcon_Atelopus_laetissumus/2-asm-falcon/p_ctg.fasta
HIFIASM_ASM=hifiasm_Sample_X.p_ctg.fasta

################### quality (QUAST) and completeness (BUSCO)

for ASM in $IPA_ASM $FALCON_ASM $HIFIASM_ASM; do
  NAME=$(basename $(dirname $ASM))
  quast.py $ASM -o quast_${NAME} --large --threads $THREADS
done

for ASM in $IPA_ASM $FALCON_ASM $HIFIASM_ASM; do
  NAME=$(basename $(dirname $ASM))
  busco -i "$ASM" -o busco_${NAME} -m genome -l $LINEAGE -c $THREADS --tar &
done
wait
