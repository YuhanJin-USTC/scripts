#!/usr/bin/env bash
set -Eeuo pipefail

# EPOCH 3D container.
SIF_PATH="/home/yuhanjin/Code_Program/Epoch/Epoch3d/epoch_epoch3d.sif"
EPOCH_EXE="epoch3d"

# Examples:
#   ./epoch3d_run.sh cases/test.deck
#   ./epoch3d_run.sh cases/test.deck 16

usage() {
    echo "Usage: $0 <input.deck> [mpi_procs]"
    echo "Example: $0 inputs/test.deck"
    echo "Example: $0 inputs/test.deck 4"
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

echo "==> Preparing EPOCH run"
echo "    input:     ${INPUT_PATH}"
echo "    container: ${SIF_PATH}"
echo "    output:    ${RESULT_DIR}"
echo "    mpi:       ${MPI_PROCS}"

mkdir -p "${RESULT_DIR}"

# Keep the original deck and the EPOCH-required input.deck.
cp "${INPUT_PATH}" "${RESULT_DIR}/${INPUT_NAME}"
cp "${INPUT_PATH}" "${RESULT_DIR}/input.deck"

# Run inside the result directory so SDF files stay isolated.
cd "${RESULT_DIR}"
RUN_PATH=$(pwd)

if [[ "${MPI_PROCS}" -gt 1 ]]; then
    echo "==> Running ${EPOCH_EXE} with MPI"
    apptainer exec --bind "${RUN_PATH}:/work" "${SIF_PATH}" \
        sh -lc "cd /work && printf '.\n' | mpirun -np ${MPI_PROCS} ${EPOCH_EXE}"
else
    echo "==> Running ${EPOCH_EXE}"
    apptainer exec --bind "${RUN_PATH}:/work" "${SIF_PATH}" \
        sh -lc "cd /work && printf '.\n' | ${EPOCH_EXE}"
fi

echo "==> Done"
echo "    output: $(pwd)"
