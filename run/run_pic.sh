#!/usr/bin/env bash
set -Eeuo pipefail

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
  if [[ "$1" == "ERROR" ]]; then
    printf '[%s] %s\n' "$(status_label "$1")" "$2" >&2
  else
    printf '[%s] %s\n' "$(status_label "$1")" "$2"
  fi
}

field() {
  printf '%s: %s\n' "$1" "$2"
}

step() {
  printf '%s\n' "$1"
}

usage() {
  printf '%s\n' \
    "Usage: $0 <target> <input> [mpi_procs]" \
    "" \
    "Run a PIC input inside the configured Apptainer image." \
    "" \
    "Targets:" \
    "  epoch1d      EPOCH 1D Generic build." \
    "  epoch2d      EPOCH 2D Generic build." \
    "  epoch3d      EPOCH 3D Generic build." \
    "  smilei       Smilei." \
    "  smilei_spin  Smilei-Spin." \
    "" \
    "Arguments:" \
    "  input        EPOCH input deck or Smilei namelist." \
    "  mpi_procs    MPI process count. Default: 1." \
    "" \
    "Options:" \
    "  -h, --help   Show this help." \
    "" \
    "Examples:" \
    "  $0 epoch2d inputs/test.deck 8" \
    "  $0 smilei inputs/tst1d.py 8"
}

print_header() {
  echo ""
  color 36 "$DISPLAY_NAME run"
  echo ""
  field "Target" "$TARGET"
  field "Mode" "run"
  field "Rule" "$EXECUTABLE in Apptainer"
  field "Input" "$INPUT_PATH"
  field "Container" "$SIF_PATH"
  field "Output" "$RESULT_DIR"
  field "MPI" "$MPI_PROCS"
  echo ""
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 1
fi

TARGET="$1"
INPUT_ARG="$2"
MPI_PROCS="${3:-1}"

case "$TARGET" in
  epoch1d)
    FAMILY="epoch"
    DISPLAY_NAME="EPOCH 1D"
    SIF_PATH="/home/yuhanjin/Code_Program/Epoch/Epoch1d/epoch_epoch1d_qed.sif"
    EXECUTABLE="epoch1d"
    ;;
  epoch2d)
    FAMILY="epoch"
    DISPLAY_NAME="EPOCH 2D"
    SIF_PATH="/home/yuhanjin/Code_Program/Epoch/Epoch2d/epoch_epoch2d.sif"
    EXECUTABLE="epoch2d"
    ;;
  epoch3d)
    FAMILY="epoch"
    DISPLAY_NAME="EPOCH 3D"
    SIF_PATH="/home/yuhanjin/Code_Program/Epoch/Epoch3d/epoch_epoch3d.sif"
    EXECUTABLE="epoch3d"
    ;;
  smilei)
    FAMILY="smilei"
    DISPLAY_NAME="Smilei"
    SIF_PATH="/home/yuhanjin/Code_Program/Smilei/Smilei_v5_1/Smilei_v5_1.sif"
    EXECUTABLE="smilei"
    ;;
  smilei_spin)
    FAMILY="smilei"
    DISPLAY_NAME="Smilei-Spin"
    SIF_PATH="/home/yuhanjin/Code_Program/Smilei_Spin/Smilei_Spin_v2_2_3D_interpolator/Smilei_Spin_v2_2_3D_interpolator.sif"
    EXECUTABLE="smilei"
    ;;
  *)
    status ERROR "Unknown target: $TARGET."
    usage >&2
    exit 1
    ;;
esac

if [[ ! -f "$INPUT_ARG" ]]; then
  status ERROR "Input file not found: $INPUT_ARG."
  exit 1
fi

INPUT_PATH=$(realpath "$INPUT_ARG")

if [[ ! "$MPI_PROCS" =~ ^[1-9][0-9]*$ ]]; then
  status ERROR "MPI process count must be a positive integer."
  exit 1
fi

if [[ ! -f "$SIF_PATH" ]]; then
  status ERROR "Container image not found: $SIF_PATH."
  exit 1
fi

if ! command -v apptainer >/dev/null 2>&1; then
  status ERROR "Apptainer is not available."
  exit 1
fi

INPUT_NAME=$(basename "$INPUT_PATH")
INPUT_BASE="${INPUT_NAME%.*}"
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
RESULT_DIR="Results_${INPUT_BASE}_${TIMESTAMP}"

print_header

# Stage the input in an isolated result directory.
mkdir -p "$RESULT_DIR"
cp "$INPUT_PATH" "$RESULT_DIR/$INPUT_NAME"

if [[ "$FAMILY" == "epoch" && "$INPUT_NAME" != "input.deck" ]]; then
  cp "$INPUT_PATH" "$RESULT_DIR/input.deck"
fi

cd "$RESULT_DIR"

if [[ "$FAMILY" == "epoch" ]]; then
  RUN_PATH=$(pwd)
  if [[ "$MPI_PROCS" -gt 1 ]]; then
    step "Running $EXECUTABLE with MPI."
    apptainer exec --bind "$RUN_PATH:/work" "$SIF_PATH" \
      sh -lc "cd /work && printf '.\n' | mpirun -np $MPI_PROCS $EXECUTABLE"
  else
    step "Running $EXECUTABLE."
    apptainer exec --bind "$RUN_PATH:/work" "$SIF_PATH" \
      sh -lc "cd /work && printf '.\n' | $EXECUTABLE"
  fi
else
  if [[ "$MPI_PROCS" -gt 1 ]]; then
    step "Running $EXECUTABLE with MPI."
    apptainer exec "$SIF_PATH" mpirun -np "$MPI_PROCS" "$EXECUTABLE" "$INPUT_NAME"
  else
    step "Running $EXECUTABLE."
    apptainer exec "$SIF_PATH" "$EXECUTABLE" "$INPUT_NAME"
  fi
fi

status OK "Run completed. Output: $(pwd)"
