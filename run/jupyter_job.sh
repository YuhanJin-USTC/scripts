#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

die() {
  printf '[ERROR] %s\n' "$1" >&2
  exit 1
}

require_var() {
  local name="$1"

  if [[ ! -v "$name" || -z "${!name}" ]]; then
    die "$name is required."
  fi
}

runtime_dir=""
state_file=""
state_tmp=""
state_owned=0
jupyter_pid=""

cleanup() {
  local exit_status=$?

  trap - EXIT INT TERM HUP
  set +e

  # Remove only this job's temporary state.
  if [[ -n "$jupyter_pid" ]]; then
    kill "$jupyter_pid" 2>/dev/null
    wait "$jupyter_pid" 2>/dev/null
  fi

  if [[ "$state_owned" -eq 1 && -n "$state_file" ]]; then
    env CODEX_TEMP_CLEANUP=1 rm -f -- "$state_file"
  fi

  if [[ -n "$state_tmp" ]]; then
    env CODEX_TEMP_CLEANUP=1 rm -f -- "$state_tmp"
  fi

  if [[ -n "$runtime_dir" ]]; then
    env CODEX_TEMP_CLEANUP=1 rm -rf -- "$runtime_dir"
  fi

  exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

require_var JUPYTER_ROOT
require_var JUPYTER_SIF
require_var JUPYTER_STATE_DIR
require_var JUPYTER_RUNTIME_BASE
require_var JUPYTER_LOG_DIR
require_var SLURM_JOB_ID
require_var SLURM_CPUS_PER_TASK

if [[ ! "$SLURM_JOB_ID" =~ ^[1-9][0-9]*$ ]]; then
  die "SLURM_JOB_ID must be numeric."
fi

if [[ ! "$SLURM_CPUS_PER_TASK" =~ ^[1-9][0-9]*$ ]]; then
  die "SLURM_CPUS_PER_TASK must be positive."
fi

if [[ ! -d "$JUPYTER_ROOT" ]]; then
  die "Jupyter root not found."
fi

if [[ ! -f "$JUPYTER_SIF" ]]; then
  die "Jupyter image not found."
fi

if [[ ! -d "$JUPYTER_STATE_DIR" ]]; then
  die "Jupyter state directory not found."
fi

if [[ ! -d "$JUPYTER_RUNTIME_BASE" ]]; then
  die "Jupyter runtime base not found."
fi

if [[ ! -d "$JUPYTER_LOG_DIR" ]]; then
  die "Jupyter log directory not found."
fi

# Restrict the Slurm-created log.
log_file="$JUPYTER_LOG_DIR/$SLURM_JOB_ID.log"
for ((attempt = 0; attempt < 20; attempt++)); do
  if [[ -e "$log_file" ]]; then
    chmod 600 "$log_file"
    break
  fi
  sleep 0.1
done
[[ -e "$log_file" ]] || die "Jupyter log file not found."

if ! command -v module >/dev/null 2>&1; then
  die "Environment modules are unavailable."
fi

if ! module load singularity/3.7.3 >/dev/null 2>&1; then
  die "Failed to load singularity/3.7.3."
fi

if ! command -v singularity >/dev/null 2>&1; then
  die "Singularity is unavailable."
fi

state_file="$JUPYTER_STATE_DIR/$SLURM_JOB_ID.state"
if [[ -e "$state_file" ]]; then
  die "State file already exists."
fi

# Isolate Jupyter runtime and user config.
runtime_dir=$(mktemp -d "$JUPYTER_RUNTIME_BASE/$SLURM_JOB_ID.XXXXXX")
chmod 700 "$runtime_dir"
mkdir "$runtime_dir/config"
chmod 700 "$runtime_dir/config"

export SINGULARITYENV_JUPYTER_RUNTIME_DIR="$runtime_dir"
export SINGULARITYENV_JUPYTER_CONFIG_DIR="$runtime_dir/config"
export SINGULARITYENV_OMP_NUM_THREADS="$SLURM_CPUS_PER_TASK"
export SINGULARITYENV_OPENBLAS_NUM_THREADS="$SLURM_CPUS_PER_TASK"

port_script=$'import secrets\nimport socket\nimport sys\n\nlow = 10000\ncount = 50001\nstart = secrets.randbelow(count)\nfor offset in range(count):\n  port = low + (start + offset) % count\n  with socket.socket() as sock:\n    try:\n      sock.bind(("0.0.0.0", port))\n    except OSError:\n      continue\n  print(port)\n  raise SystemExit(0)\nraise SystemExit(1)'

# Pick a compute-node port inside the image.
if ! port=$(singularity exec --cleanenv \
  --bind "$JUPYTER_ROOT:$JUPYTER_ROOT" \
  --pwd "$JUPYTER_ROOT" \
  "$JUPYTER_SIF" python3 -c "$port_script" 2>/dev/null); then
  die "No free Jupyter port found."
fi

if [[ ! "$port" =~ ^[0-9]+$ || "$port" -lt 10000 || "$port" -gt 60000 ]]; then
  die "Invalid Jupyter port."
fi

# Start the immutable image runscript.
singularity run --cleanenv \
  --bind "$JUPYTER_ROOT:$JUPYTER_ROOT" \
  --pwd "$JUPYTER_ROOT" \
  "$JUPYTER_SIF" \
  --no-browser \
  --ServerApp.root_dir="$JUPYTER_ROOT" \
  --ServerApp.ip=0.0.0.0 \
  --ServerApp.port="$port" \
  --ServerApp.port_retries=0 \
  --ServerApp.log_level=WARN &
jupyter_pid=$!

json_script=$'import json\nimport socket\nimport sys\n\nwith open(sys.argv[1], encoding="utf-8") as stream:\n  data = json.load(stream)\nprint(socket.gethostname())\nprint(data["port"])\nprint(data["token"])'

server_data=""
# Read token data from the private runtime file.
for ((attempt = 0; attempt < 120; attempt++)); do
  if ! kill -0 "$jupyter_pid" 2>/dev/null; then
    wait "$jupyter_pid" 2>/dev/null || true
    jupyter_pid=""
    die "Jupyter exited before startup."
  fi

  shopt -s nullglob
  server_files=("$runtime_dir"/jpserver-*.json)
  shopt -u nullglob

  if [[ "${#server_files[@]}" -gt 1 ]]; then
    die "Multiple Jupyter server files found."
  fi

  if [[ "${#server_files[@]}" -eq 1 ]]; then
    if server_data=$(singularity exec --cleanenv \
      --bind "$JUPYTER_ROOT:$JUPYTER_ROOT" \
      --pwd "$JUPYTER_ROOT" \
      "$JUPYTER_SIF" python3 -c "$json_script" \
      "${server_files[0]}" 2>/dev/null); then
      break
    fi
  fi

  sleep 1
done

if [[ -z "$server_data" ]]; then
  die "Timed out waiting for Jupyter."
fi

mapfile -t server_lines <<< "$server_data"
if [[ "${#server_lines[@]}" -ne 3 ]]; then
  die "Invalid Jupyter server data."
fi

node="${server_lines[0]}"
server_port="${server_lines[1]}"
token="${server_lines[2]}"

if [[ -z "$node" || -z "$token" ]]; then
  die "Jupyter authentication data is missing."
fi

if [[ ! "$server_port" =~ ^[0-9]+$ || "$server_port" -ne "$port" ]]; then
  die "Jupyter port does not match."
fi

if ! token_b64=$(printf '%s' "$token" | base64 -w0); then
  die "Failed to encode Jupyter token."
fi

state_tmp=$(mktemp "$JUPYTER_STATE_DIR/.$SLURM_JOB_ID.state.XXXXXX")
chmod 600 "$state_tmp"
# Publish a fixed state format atomically.
{
  printf 'version=1\n'
  printf 'node=%s\n' "$node"
  printf 'port=%s\n' "$server_port"
  printf 'token_b64=%s\n' "$token_b64"
} > "$state_tmp"
mv -- "$state_tmp" "$state_file"
state_tmp=""
state_owned=1

unset token token_b64 server_data server_lines

# Keep the allocation alive with Jupyter.
if wait "$jupyter_pid"; then
  jupyter_status=0
else
  jupyter_status=$?
fi
jupyter_pid=""

if [[ "$jupyter_status" -ne 0 ]]; then
  die "Jupyter exited with status $jupyter_status."
fi
