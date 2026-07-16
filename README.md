# PACBIO Genome Assemblying

De novo genome assembly from PacBio HiFi reads using three assemblers, followed by quality
assessment of each resulting assembly. Set the script accordingly to your HPC capacity. Don't forget to load modules.
If they're not available on your HPC, you can ask the HPC administrators or, preferably, install them with conda.

## Pipeline

- `cutadapt` to remove residual PacBio adapter sequence from HiFi reads
- assembly with `IPA`, `hifiasm`, and `Falcon` in parallel, run independently on the same trimmed
  reads
- `QUAST` for contiguity statistics on each of the three assemblies
- `BUSCO` (vertebrata_odb10) for gene-completeness assessment on each of the three assemblies

## Input

- `Sample_X.hifi.fastq.gz`: raw PacBio HiFi reads, one file per individual
- `fc_run_Sample_X.cfg`: Falcon config file, genome_size and length_cutoff set per sample

## Output

- `hifiasm_Sample_X.p_ctg.fasta`, `ipa_Sample_X/assembly-results/final.p_ctg.fasta`,
  `falcon_Sample_X/2-asm-falcon/p_ctg.fasta`: primary contig assemblies, one per assembler
- `quast_*/`, `busco_*/`: assessment reports used to pick the best assembly to carry forward

The assembly chosen from this step is the reference fasta used in `03-variant-calling`,
`04-reference-consensus`, and `05-psmc-demographic-history`.

## Genome assembly (and adapters trimming)

```
# HiFi reads still carry PacBio adapter remnants at chimeric junctions, cutadapt clears them before assembly
cutadapt \
  -g AAAAAAAAAAAAAAAAAATTAACGGAGGAGGAGGA \
  -e 0.1 -O 20 \
  -o Sample_X.hifi.trimmed.fastq.gz \
  $RAW

TRIMMED=Sample_X.hifi.trimmed.fastq.gz

# IPA
ipa local \
  --nthreads $THREADS \
  -i $TRIMMED \
  --run-dir ipa_Sample_X

# hifiasm, -l0 disables the internal purge step since duplication is handled separately downstream
hifiasm -o hifiasm_Sample_X -t $THREADS -l0 $TRIMMED
awk '/^S/{print ">"$2"\n"$3}' hifiasm_Sample_X.bp.p_ctg.gfa > hifiasm_Sample_X.p_ctg.fasta

# Falcon needs an fc_run.cfg with genome_size and length_cutoff set for this sample, pointing to $TRIMMED
fc_run fc_run_Sample_X.cfg

IPA_ASM=ipa_Sample_X/assembly-results/final.p_ctg.fasta
FALCON_ASM=falcon_Sample_X/2-asm-falcon/p_ctg.fasta
HIFIASM_ASM=hifiasm_Sample_X.p_ctg.fasta
```

## Quality assesment with QUAST

```
for ASM in $IPA_ASM $FALCON_ASM $HIFIASM_ASM; do
  NAME=$(basename $(dirname $ASM))
  quast.py $ASM -o quast_${NAME} --large --threads $THREADS
done
```

## BUSCO (Completeness assessment)

```
LINEAGE=vertebrata_odb10

for ASM in $IPA_ASM $FALCON_ASM $HIFIASM_ASM; do
  NAME=$(basename $(dirname $ASM))
  busco -i "$ASM" -o busco_${NAME} -m genome -l $LINEAGE -c $THREADS --tar &
done
wait
```

## Notes

To use BUSCO, you need the `vertebrata_odb10` lineage dataset downloaded
locally beforehand.
