#!/bin/bash
# path for all query and reference data files
DATA_DIR="./aFischeri_Data"
# list with all aFischeri query accessions
QUERY_LIST=("SRR11648416" "SRR11648417" "SRR11648418" "SRR11648419" "SRR11648420" "SRR11648421")
# path for reference genome
REF="${DATA_DIR}/GCF_000011805.1_ASM1180v1_genomic.fna"

# log to console and log-file
exec > >(tee -a "benchmark_log.txt") 2>&1

# log time
START="$(date +"%T")"
echo "Start Time: $START"

if [[ "$1" != "--no-setup" ]]; then
    # setup SRA toolkit
    echo "Setting up SRA toolkit"
    wget --output-document sratoolkit.tar.gz https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/current/sratoolkit.current-ubuntu64.tar.gz
    tar -xzf sratoolkit.tar.gz
    rm -f sratoolkit.tar.gz
    mv sratoolkit* sratoolkit

    # setup NCBI's datasets
    echo "Setting up NCBI's datasets."
    wget -O datasets https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/v2/linux-amd64/datasets
    chmod +x datasets

    # setup directories
    echo "Setting up directories."
    mkdir -p "$DATA_DIR"
    mkdir -p "${DATA_DIR}/tmp"

    # download the ref
    echo "Downloading the six reference genome."
    ./datasets download genome accession GCF_000011805.1 --include genome --filename "${DATA_DIR}/GCF_000011805.1.zip"
    unzip "${DATA_DIR}/GCF_000011805.1.zip" -d "${DATA_DIR}/tmp"
    mv "${DATA_DIR}/tmp/ncbi_dataset/data/GCF_000011805.1/GCF_000011805.1_ASM1180v1_genomic.fna" "$REF"
    rm -rf "${DATA_DIR}/tmp"
    rm "${DATA_DIR}/GCF_000011805.1.zip"

    # download the queries from NCBI
    echo "Downloading the query sequences."
    cd "${DATA_DIR}"
    for SRR in "${QUERY_LIST[@]}"; do
        echo "Downloading ${SRR}."
        ../sratoolkit/bin/fasterq-dump $SRR
    done
    cd "../"
fi

echo "Setup complete."

declare -A VARIANTS=(
    ["minimap2"]="minimap2/minimap2"
    ["minimap2_mod-mini"]="minimap2_mod-mini/minimap2"
    ["minimap2_mod-mini_w8"]="minimap2_mod-mini/minimap2 -w 8"
)
declare -A FLAGS=(
    ["default"]="-a"
    ["HPC"]="-a -H"
    ["SR"]="-a -x sr"
)

echo "Starting benchmark"
# run all variants with all flags on all runs
for VARIANT_NAME in "${!VARIANTS[@]}"; do
    OUT_PRE="./out/${VARIANT_NAME}"

    for FLAG_NAME in "${!FLAGS[@]}"; do
        OUT_DIR="${OUT_PRE}_${FLAG_NAME}"
        COMMAND="../${VARIANTS[$VARIANT_NAME]}"
        FLAG="${FLAGS[$FLAG_NAME]}"

        if [[ "$COMMAND" == *" -w 8" ]]; then
            COMMAND="${COMMAND// -w 8/}"
            FLAG="$FLAG -w 8"
        fi

        # reset eval output directory for current setting
        rm -rf "${OUT_DIR}"
        mkdir -p "${OUT_DIR}"

        for SRR in "${QUERY_LIST[@]}"; do
            # prepare log file
            LOG="${OUT_DIR}/${SRR}_eval.txt"
            touch "${LOG}"
            QUERY_FILE1="${DATA_DIR}/${SRR}_1.fastq"
            QUERY_FILE2="${DATA_DIR}/${SRR}_2.fastq"
            echo -e "$COMMAND $FLAG $REF $QUERY_FILE1 $QUERY_FILE2\n" >> "${LOG}"

            echo "Running $COMMAND $FLAG $REF $QUERY_FILE1 $QUERY_FILE2"

            # runs minimap
            # prepend sudo chrt -f 99 for more deterministic runtime
            $COMMAND $FLAG $REF $QUERY_FILE1 $QUERY_FILE2 > "${OUT_DIR}/tmp.sam" 2> >(tee -a "${LOG}" >&2)

            echo "Run Completed, now calculating evaluation metrics."
            # result sam to bam
            samtools view -b "${OUT_DIR}/tmp.sam" > "${OUT_DIR}/tmp.bam"

            # get result flagstat
            echo -e "\nFlagstat:" >> "${LOG}"
            samtools flagstat "${OUT_DIR}/tmp.bam" >> "${LOG}"

            # calculate MAPQ>=30
            echo -e "\n" >> "${LOG}"
            echo "MAPQ(>=30):" >> "${LOG}"
            samtools view -c -q 30 "${OUT_DIR}/tmp.bam" >> "${LOG}"
        done

        # cleanup
        rm -f "${OUT_DIR}/tmp"*
    done
done

# log time
END="$(date +"%T")"
echo "Start Time: $END"
