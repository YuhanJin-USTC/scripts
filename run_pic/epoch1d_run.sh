#!/usr/bin/env bash
set -Eeuo pipefail

# EPOCH 1D container.
SIF_PATH="/home/yuhanjin/Code_Program/Epoch/Epoch1d/epoch_epoch1d_qed_work.sif"
EPOCH_EXE="epoch1d"

color() {
    printf '\033[%sm%s\033[0m' "$1" "$2"
}

status_label() {
    case "$1" in
        OK) color 32 OK ;;
        ERROR) color 31 ERROR ;;
        *) printf '%s' "$1" ;;
    esac
}

status() {
    printf '[%s] %s\n' "$(status_label "$1")" "$2"
}

field() {
    printf '%s: %s\n' "$1" "$2"
}

usage() {
    printf '%s\n' \
        "Usage: $0 <input.deck> [mpi_procs]" \
        "" \
        "Run an EPOCH 1D input deck inside the configured Apptainer image." \
        "" \
        "Arguments:" \
        "  input.deck  EPOCH input deck." \
        "  mpi_procs   MPI process count. Default: 1." \
        "" \
        "Options:" \
        "  -h, --help  Show this help." \
        "" \
        "Examples:" \
        "  $0 inputs/test.deck" \
        "  $0 inputs/test.deck 4"
}

print_header() {
    echo ""
    color 36 "EPOCH 1D run"
    echo ""
    field "Target" "${INPUT_PATH}"
    field "Mode" "run"
    field "Rule" "${EPOCH_EXE} in Apptainer"
    field "Container" "${SIF_PATH}"
    field "Output" "${RESULT_DIR}"
    field "MPI" "${MPI_PROCS}"
    echo ""
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 1
fi

MPI_PROCS="${2:-1}"

if [[ ! -f "$1" ]]; then
    status ERROR "input file not found: $1" >&2
    exit 1
fi

INPUT_PATH=$(realpath "$1")

if [[ ! "${MPI_PROCS}" =~ ^[1-9][0-9]*$ ]]; then
    status ERROR "mpi_procs must be a positive integer." >&2
    exit 1
fi

if [[ ! -f "${SIF_PATH}" ]]; then
    status ERROR "container image not found: ${SIF_PATH}" >&2
    exit 1
fi

if ! command -v apptainer >/dev/null 2>&1; then
    status ERROR "apptainer is not available." >&2
    exit 1
fi

INPUT_NAME=$(basename "${INPUT_PATH}")
INPUT_BASE="${INPUT_NAME%.*}"
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
RESULT_DIR="Results_${INPUT_BASE}_${TIMESTAMP}"

print_header

# Stage input files in an isolated result directory.
mkdir -p "${RESULT_DIR}"

# Keep the original deck and the EPOCH-required input.deck.
cp "${INPUT_PATH}" "${RESULT_DIR}/${INPUT_NAME}"
cp "${INPUT_PATH}" "${RESULT_DIR}/input.deck"

# Run inside the result directory so SDF files stay isolated.
cd "${RESULT_DIR}"
RUN_PATH=$(pwd)

if [[ "${MPI_PROCS}" -gt 1 ]]; then
    status OK "Running ${EPOCH_EXE} with MPI."
    apptainer exec --bind "${RUN_PATH}:/work" "${SIF_PATH}" \
        sh -lc "cd /work && printf '.\n' | mpirun -np ${MPI_PROCS} ${EPOCH_EXE}"
else
    status OK "Running ${EPOCH_EXE}."
    apptainer exec --bind "${RUN_PATH}:/work" "${SIF_PATH}" \
        sh -lc "cd /work && printf '.\n' | ${EPOCH_EXE}"
fi

status OK "Run complete. Output: $(pwd)"
