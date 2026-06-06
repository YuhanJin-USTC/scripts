#!/usr/bin/env bash
set -Eeuo pipefail

# Smilei container.
SIF_PATH="/home/yuhanjin/Code_Program/Smilei/Smilei_v5_1/Smilei_v5_1.sif"
SMILEI_EXE="smilei"

# Examples:
#   ./smilei_run.sh cases/tst1d.py
#   ./smilei_run.sh cases/tst2d.py 8

usage() {
    echo "Usage: $0 <input.py> [mpi_procs]"
    echo "Example: $0 inputs/tst1d.py"
    echo "Example: $0 inputs/tst1d.py 4"
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 1
fi

MPI_PROCS="${2:-1}"

if [[ ! -f "$1" ]]; then
    echo "Error: input file not found: $1" >&2
    exit 1
fi

INPUT_PATH=$(realpath "$1")

if [[ ! "${MPI_PROCS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: mpi_procs must be a positive integer." >&2
    exit 1
fi

if [[ ! -f "${SIF_PATH}" ]]; then
    echo "Error: container image not found: ${SIF_PATH}" >&2
    exit 1
fi

if ! command -v apptainer >/dev/null 2>&1; then
    echo "Error: apptainer is not available." >&2
    exit 1
fi

INPUT_NAME=$(basename "${INPUT_PATH}")
INPUT_BASE="${INPUT_NAME%.*}"
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
RESULT_DIR="Results_${INPUT_BASE}_${TIMESTAMP}"

echo "==> Preparing Smilei run"
echo "    input:     ${INPUT_PATH}"
echo "    container: ${SIF_PATH}"
echo "    output:    ${RESULT_DIR}"
echo "    mpi:       ${MPI_PROCS}"

mkdir -p "${RESULT_DIR}"

# Keep a copy of the namelist in the output directory.
cp "${INPUT_PATH}" "${RESULT_DIR}/${INPUT_NAME}"

# Run inside the result directory so Smilei outputs stay isolated.
cd "${RESULT_DIR}"

if [[ "${MPI_PROCS}" -gt 1 ]]; then
    echo "==> Running ${SMILEI_EXE} with MPI"
    # Use the MPI runtime inside the container.
    apptainer exec "${SIF_PATH}" mpirun -np "${MPI_PROCS}" "${SMILEI_EXE}" "${INPUT_NAME}"
else
    echo "==> Running ${SMILEI_EXE}"
    apptainer exec "${SIF_PATH}" "${SMILEI_EXE}" "${INPUT_NAME}"
fi

echo "==> Done"
echo "    output: $(pwd)"
