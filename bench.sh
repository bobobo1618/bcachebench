#!/bin/bash
if [ "$#" -ne 2 ]; then
    echo "Compares bcachefs to other filesystems and packages output."
    echo "Requires: fio, mkfs.<filesystem>, mktemp, zip, sed, wipefs, bcache, block device with at least 10G of space."
    echo "Usage: benchmark.sh [btrfs,ext4,xfs] <block_device>"
    echo "Benchmark bundle is output to <timestamp>-<filesystems>.zip"
    echo "WARNING: Given device will be erased."
    exit 1
fi

FILESYSTEMS="$1"
DEVICE="$2"
TIMESTAMP=$(date '+%s.%N')
FIO_TEMPLATE=fio.template.conf
MOUNTPOINT="$(mktemp -d)"
SED_ESCAPED_MOUNTPOINT="$(echo ${MOUNTPOINT} | sed -e 's/[\/&]/\\&/g')"

# Benchmarking function
bench() {
    # Setup variables
    FIO_CONF="$(mktemp)"
    FILESYSTEM="$1"
    OUTPUT_DIR="$2"
    PREFIX="${OUTPUT_DIR}/${FILESYSTEM}"

    # Prepare fio config file
    SED_ESCAPED_PREFIX="$(echo ${PREFIX} | sed -e 's/[\/&]/\\&/g')"
    cat "${FIO_TEMPLATE}" | sed -e "s/<log_prefix>/${SED_ESCAPED_PREFIX}/; s/<mountpoint>/${SED_ESCAPED_MOUNTPOINT}/" > "${FIO_CONF}"

    # Prepare filesystem
    wipefs -a "${DEVICE}"
    if [[ "${FILESYSTEM}" == "bcache" ]]; then
        bcache format "${DEVICE}"
    else
        "mkfs.${FILESYSTEM}" "${DEVICE}"
    fi

    # Mount
    mount "${DEVICE}" "${MOUNTPOINT}"

    # Benchmark
    fio "${FIO_CONF}"

    # Cleanup
    rm "${FIO_CONF}"
    umount "${DEVICE}"
}

OUTPUT_DIR="$(mktemp -d)"
bench bcache "${OUTPUT_DIR}"

for fs in ${FILESYSTEMS//,/ }; do
    bench "$fs" "${OUTPUT_DIR}"
done

zip -r -D -j "${TIMESTAMP}-${FILESYSTEMS}.zip" "${OUTPUT_DIR}"
rmdir "${MOUNTPOINT}"