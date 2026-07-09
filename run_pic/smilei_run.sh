#!/usr/bin/env bash
set -Eeuo pipefail

# Smilei container.
SIF_PATH="/home/yuhanjin/Code_Program/Smilei/Smilei_v5_1/Smilei_v5_1.sif"
SMILEI_EXE="smilei"

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
        "Usage: $0 <input.py> [mpi_procs]" \
        "" \
        "Run a Smilei namelist inside the configured Apptainer image." \
        "" \
        "Arguments:" \
        "  input.py    Smilei namelist." \
        "  mpi_procs   MPI process count. Default: 1." \
        "" \
        "Options:" \
        "  -h, --help  Show this help." \
        "" \
        "Examples:" \
        "  $0 inputs/tst1d.py" \
        "  $0 inputs/tst1d.py 8"
}

print_header() {
    echo ""
    color 36 "Smilei run"
    echo ""
    field "Target" "${INPUT_PATH}"
    field "Mode" "run"
    field "Rule" "${SMILEI_EXE} in Apptainer"
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

# Stage the namelist in an isolated result directory.
mkdir -p "${RESULT_DIR}"

# Keep a copy of the namelist in the output directory.
cp "${INPUT_PATH}" "${RESULT_DIR}/${INPUT_NAME}"

# Run inside the result directory so Smilei outputs stay isolated.
cd "${RESULT_DIR}"

if [[ "${MPI_PROCS}" -gt 1 ]]; then
    status OK "Running ${SMILEI_EXE} with MPI."
    # Use the MPI runtime inside the container.
    apptainer exec "${SIF_PATH}" mpirun -np "${MPI_PROCS}" "${SMILEI_EXE}" "${INPUT_NAME}"
else
    status OK "Running ${SMILEI_EXE}."
    apptainer exec "${SIF_PATH}" "${SMILEI_EXE}" "${INPUT_NAME}"
fi

status OK "Run complete. Output: $(pwd)"