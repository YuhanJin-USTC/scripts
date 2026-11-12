#!/bin/sh
#SBATCH -J <job_name>
#SBATCH -p <partition>
#SBATCH --nodes=<nodes>
#SBATCH --ntasks=<total_ranks>
#SBATCH --ntasks-per-node=<ranks_per_node>
#SBATCH --cpus-per-task=<threads>
#SBATCH -A <account>
#SBATCH --qos=<qos>
#SBATCH -t <time_limit>
#SBATCH -o out_%j.log
#SBATCH -e err_%j.log
##SBATCH --constraint=<32core_or_64core>

# WZ: wzacnormal (128 CPUs), wzacnormal04 (64), wzhcnormal (32/64).
#     Account ac58qn21ek, provider mlx, HOME /work/home/yuhanjin.
# HF: hfacnormal01/02/04 (128 CPUs).
#     Account ac58qn21ek, provider psm2, HOME /public/home/yuhanjin.
# TY: tyhcnormal (32/64 CPUs).
#     Account shiyin, provider mlx, HOME /work/home/yuhanjin.
# All sites: QoS user_yuhanjin. Select 32core or 64core for mixed partitions.
# total_ranks = nodes * ranks_per_node; ranks_per_node * threads <= CPUs/node.
# Fill the header and paths, then submit from the case directory.
# For TCP: sbatch --export=ALL,I_MPI_OFI_PROVIDER=tcp smilei_jobsub.sh

case "${1:-}" in
  -h|--help)
    printf '%s\n' \
      "Usage: sbatch smilei_jobsub.sh" \
      "Help: sh smilei_jobsub.sh --help" \
      "Run the configured Smilei input with host Intel MPI and Singularity." \
      "Arguments: none; fill the SBATCH placeholders and paths before submission." \
      "Options: -h, --help  Show this help without starting a job." \
      "Example: sbatch --export=ALL,I_MPI_OFI_PROVIDER=tcp smilei_jobsub.sh"
    exit 0
    ;;
esac
if [ "$#" -ne 0 ]; then
  echo "[ERROR] unexpected arguments; use --help." >&2
  exit 1
fi

SMILEI_SIF="${HOME}/Code_Program/Smilei/Smilei_v5_1/Smilei_v5_1.sif"
# Smilei-Spin: replace the SIF path with the following line.
# SMILEI_SIF="${HOME}/Code_Program/Smilei_Spin/Smilei_Spin_v2_2_3D_interpolator/Smilei_Spin_v2_2_3D_interpolator.sif"
HDF5_ROOT="/opt/.local/program/hdf5"
SOURCE_INPUT="input.py"

if [ -z "${SLURM_JOB_ID:-}" ] || [ -z "${SLURM_NTASKS:-}" ] || [ -z "${SLURM_CPUS_PER_TASK:-}" ]; then
  echo "[ERROR] submit with sbatch and set ntasks and cpus-per-task." >&2
  exit 1
fi

case "${SLURM_JOB_PARTITION:-}" in
  hfacnormal01|hfacnormal02|hfacnormal04) PROVIDER="${I_MPI_OFI_PROVIDER:-psm2}" ;;
  wzacnormal|wzacnormal04|wzhcnormal|tyhcnormal) PROVIDER="${I_MPI_OFI_PROVIDER:-mlx}" ;;
  *)
    echo "[ERROR] unsupported partition: ${SLURM_JOB_PARTITION:-unset}" >&2
    exit 1
    ;;
esac

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OMP_SCHEDULE=dynamic
export OMP_PROC_BIND=true
export I_MPI_PIN_DOMAIN=omp

module purge || exit $?
module load mpi/intelmpi/2021.3.0 || exit $?
module load singularity/3.7.3 || exit $?

MPI_BIND="${I_MPI_ROOT}:${I_MPI_ROOT}:ro"
MPI_LIBS="${I_MPI_ROOT}/lib/release:${I_MPI_ROOT}/lib:${I_MPI_ROOT}/libfabric/lib"
case "${PROVIDER}" in
  mlx)
    UCX_ROOT=/opt/hpc/software/mpi/hpcx/v2.11.0/ucx_without_rocm
    MPI_BIND="${MPI_BIND},${UCX_ROOT}:${UCX_ROOT}:ro"
    MPI_LIBS="${MPI_LIBS}:${UCX_ROOT}/lib"
    ;;
  psm2)
    MPI_BIND="${MPI_BIND},/lib64/libpsm2.so.2:/usr/lib/x86_64-linux-gnu/libpsm2.so.2:ro"
    ;;
esac
export SINGULARITYENV_I_MPI_ROOT="${I_MPI_ROOT}"
export SINGULARITYENV_LD_LIBRARY_PATH="${MPI_LIBS}:${HDF5_ROOT}/lib"
export SINGULARITYENV_FI_PROVIDER_PATH="${I_MPI_ROOT}/libfabric/lib/prov"
export SINGULARITYENV_I_MPI_FABRICS=shm:ofi
export SINGULARITYENV_I_MPI_OFI_PROVIDER="${PROVIDER}"
export SINGULARITYENV_I_MPI_DEBUG="${I_MPI_DEBUG:-1}"

if [ ! -f "${SOURCE_INPUT}" ]; then
  echo "[ERROR] missing Smilei input: ${SOURCE_INPUT}" >&2
  exit 1
fi
if [ ! -f "${SMILEI_SIF}" ]; then
  echo "[ERROR] missing Smilei SIF: ${SMILEI_SIF}" >&2
  exit 1
fi

TIMESTAMP=$(date "+%Y%m%d_%H%M%S") || exit $?
SOURCE_INPUT_NAME=$(basename "${SOURCE_INPUT}") || exit $?
INPUT_BASENAME="${SOURCE_INPUT_NAME%.*}"
RESULT_DIR="Results_${INPUT_BASENAME}_${TIMESTAMP}_${SLURM_JOB_ID}"
CASE_DIR_ABS=$(pwd -P) || exit $?
RESULT_DIR_ABS="${CASE_DIR_ABS}/${RESULT_DIR}"

printf '%s\n' "" "Smilei Slurm run" \
  "Target: smilei" \
  "Mode: run" \
  "Rule: host MPI with Singularity" \
  "Job: ${SLURM_JOB_ID}" \
  "Nodes: ${SLURM_JOB_NODELIST}" \
  "MPI: ${SLURM_NTASKS}" \
  "Threads: ${OMP_NUM_THREADS}" \
  "Provider: ${PROVIDER}" \
  "Input: ${SOURCE_INPUT}" \
  "Container: ${SMILEI_SIF}" \
  "Output: ${RESULT_DIR_ABS}"

echo "[1/2] Staging input."
if ! mkdir "${RESULT_DIR_ABS}"; then
  echo "[ERROR] cannot create new result directory: ${RESULT_DIR_ABS}" >&2
  exit 1
fi
cp "${SOURCE_INPUT}" "${RESULT_DIR_ABS}/${SOURCE_INPUT_NAME}" || exit $?
cd "${RESULT_DIR_ABS}" || exit 1

echo "[2/2] Running Smilei."
mpiexec -n "${SLURM_NTASKS}" \
  singularity exec \
  --bind "${MPI_BIND}" \
  --bind "${HOME}:${HOME}" \
  --pwd "${RESULT_DIR_ABS}" \
  "${SMILEI_SIF}" \
  smilei "${SOURCE_INPUT_NAME}"
RUN_STATUS=$?

if [ "${RUN_STATUS}" -ne 0 ]; then
  echo "[ERROR] Smilei exited with status ${RUN_STATUS}" >&2
  exit "${RUN_STATUS}"
fi

echo "[OK] Run completed. Output: ${RESULT_DIR_ABS}"
