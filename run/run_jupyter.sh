#!/usr/bin/env bash
set -Eeuo pipefail

# Local entry configuration.
SSH_CONFIG="/home/yuhanjin/.ssh/config"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
JOB_SCRIPT="$SCRIPT_DIR/jupyter_job.sh"
JOB_NAME="epoch-jupyter"
DEFAULT_CPUS=64
DEFAULT_MEM="230G"
DEFAULT_TIME="2-00:00:00"

SSH_OPTIONS=(
  -F "$SSH_CONFIG"
  -o ConnectTimeout=20
  -o ServerAliveInterval=60
  -o ServerAliveCountMax=3
)

ACTIVE_CLUSTER=""
ACTIVE_JOB_ID=""
TUNNEL_PID=""

color() {
  printf '\033[%sm%s\033[0m' "$1" "$2"
}

status_label() {
  case "$1" in
    OK) color 32 OK ;;
    WARN) color 33 WARN ;;
    ERROR) color 31 ERROR ;;
    WAIT) color 36 WAIT ;;
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

die() {
  status ERROR "$1"
  exit 1
}

usage() {
  printf '%s\n' \
    "Usage:" \
    "  run_jupyter.sh start <cluster> [remote_dir] [options]" \
    "  run_jupyter.sh status <cluster> [job_id]" \
    "  run_jupyter.sh connect <cluster> <job_id>" \
    "  run_jupyter.sh stop <cluster> <job_id>" \
    "" \
    "Open and manage Slurm-backed EPOCH JupyterLab sessions." \
    "" \
    "Clusters:" \
    "  wzcluster  /work/home/yuhanjin, wzacnormal04" \
    "  tycluster  /work/home/yuhanjin, tyhcnormal" \
    "  hfcluster  /public/home/yuhanjin, hfacnormal04" \
    "" \
    "Start options:" \
    "  --cpus N          CPU count. Default: 64." \
    "  --mem SIZE        Slurm memory. Default: 230G." \
    "  --time TIME       Slurm time. Default: 2-00:00:00." \
    "  --partition NAME  Override the configured partition." \
    "  -h, --help        Show this help." \
    "" \
    "Examples:" \
    "  run_jupyter start wzcluster" \
    "  run_jupyter start wzcluster /work/home/yuhanjin/Simulation/case_a" \
    "  run_jupyter status wzcluster" \
    "  run_jupyter connect wzcluster 123456" \
    "  run_jupyter stop wzcluster 123456"
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || die "Command not found: $1."
}

select_cluster() {
  # Cluster configuration.
  CLUSTER="$1"
  case "$CLUSTER" in
    wzcluster)
      REMOTE_ROOT="/work/home/yuhanjin"
      PARTITION="wzacnormal04"
      ACCOUNT="ac58qn21ek"
      ;;
    tycluster)
      REMOTE_ROOT="/work/home/yuhanjin"
      PARTITION="tyhcnormal"
      ACCOUNT="shiyin"
      ;;
    hfcluster)
      REMOTE_ROOT="/public/home/yuhanjin"
      PARTITION="hfacnormal04"
      ACCOUNT="ac58qn21ek"
      ;;
    *)
      die "Unknown cluster: $CLUSTER."
      ;;
  esac

  QOS="user_yuhanjin"
  SIF_PATH="$REMOTE_ROOT/Code_Program/Post_Process/Epoch/epoch_jupyter.sif"
  SESSION_BASE="$REMOTE_ROOT/.cache/epoch_jupyter"
  STATE_DIR="$SESSION_BASE/states"
  RUNTIME_BASE="$SESSION_BASE/runtime"
  LOG_DIR="$SESSION_BASE/logs"
}

validate_job_id() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]] || die "Job ID must be a positive integer."
}

validate_start_values() {
  # Reject unsafe values before SSH.
  [[ "$CPUS" =~ ^[1-9][0-9]*$ ]] || die "CPU count must be a positive integer."
  [[ "$MEMORY" =~ ^[1-9][0-9]*[KMGTP]?$ ]] || die "Memory must be a positive Slurm size such as 120G."
  [[ "$WALLTIME" =~ ^([0-9]+-)?[0-9]{1,2}:[0-5][0-9]:[0-5][0-9]$ ]] || die "Time must use [days-]hours:minutes:seconds."
  [[ "$PARTITION" =~ ^[A-Za-z0-9_.-]+$ ]] || die "Partition contains unsupported characters."
  [[ "$REMOTE_DIR" == /* ]] || die "Remote directory must be absolute."
  [[ "$REMOTE_DIR" != *$'\n'* && "$REMOTE_DIR" != *$'\r'* && "$REMOTE_DIR" != *,* ]] || die "Remote directory contains unsupported characters."
  case "$REMOTE_DIR" in
    "$REMOTE_ROOT"|"$REMOTE_ROOT"/*) ;;
    *) die "Remote directory must stay below $REMOTE_ROOT." ;;
  esac
}

require_local_start_tools() {
  check_command ssh
  check_command python3
  check_command curl
  check_command base64
  check_command cmd.exe
  [[ -r "$SSH_CONFIG" ]] || die "SSH config is not readable: $SSH_CONFIG."
  [[ -r "$JOB_SCRIPT" ]] || die "Slurm job script is not readable: $JOB_SCRIPT."
}

require_local_ssh() {
  check_command ssh
  [[ -r "$SSH_CONFIG" ]] || die "SSH config is not readable: $SSH_CONFIG."
}

remote_command() {
  # Quote one remote command without eval.
  local command=""
  local quoted
  local arg

  for arg in "$@"; do
    printf -v quoted '%q' "$arg"
    if [[ -z "$command" ]]; then
      command="$quoted"
    else
      command+=" $quoted"
    fi
  done
  printf '%s' "$command"
}

remote_exec() {
  local command
  command=$(remote_command "$@")
  ssh "${SSH_OPTIONS[@]}" "$CLUSTER" "$command"
}

remote_bash() {
  local command
  command=$(remote_command bash -l -s -- "$@")
  ssh "${SSH_OPTIONS[@]}" "$CLUSTER" "$command"
}

show_upload_command() {
  status ERROR "Remote SIF is missing: $SIF_PATH"
  printf '%s\n' \
    "Upload it separately, then retry:" \
    "  win2clst $CLUSTER \\" \
    "    /home/yuhanjin/Code_Program/Post_Process/Epoch \\" \
    "    $REMOTE_ROOT/Code_Program/Post_Process/Epoch \\" \
    "    --run --all-files"
}

remote_preflight() {
  local output
  local exit_code

  # Check paths and tools before remote writes.
  set +e
  output=$(remote_bash "$REMOTE_ROOT" "$REMOTE_DIR" "$SIF_PATH" <<'REMOTE'
set -Eeuo pipefail

root_dir="$1"
requested_dir="$2"
sif_path="$3"

for name in realpath sbatch squeue scancel; do
  command -v "$name" >/dev/null 2>&1 || {
    printf 'Remote command not found: %s.\n' "$name" >&2
    exit 40
  }
done

root_real=$(realpath -e -- "$root_dir") || {
  printf 'Remote root not found: %s.\n' "$root_dir" >&2
  exit 41
}
requested_real=$(realpath -e -- "$requested_dir") || {
  printf 'Remote directory not found: %s.\n' "$requested_dir" >&2
  exit 41
}
[[ -d "$requested_real" ]] || {
  printf 'Remote path is not a directory: %s.\n' "$requested_real" >&2
  exit 41
}

case "$requested_real" in
  "$root_real"|"$root_real"/*) ;;
  *)
    printf 'Remote directory escapes configured root: %s.\n' "$requested_real" >&2
    exit 41
    ;;
esac

[[ -r "$sif_path" ]] || exit 42
type module >/dev/null 2>&1 || {
  printf 'Environment modules are unavailable.\n' >&2
  exit 40
}
module load singularity/3.7.3 >/dev/null 2>&1 || {
  printf 'Cannot load singularity/3.7.3.\n' >&2
  exit 40
}
command -v singularity >/dev/null 2>&1 || {
  printf 'Singularity is unavailable after module load.\n' >&2
  exit 40
}

printf '%s\n' "$requested_real"
REMOTE
  )
  exit_code=$?
  set -e

  if [[ $exit_code -eq 42 ]]; then
    show_upload_command
    return 42
  fi
  if [[ $exit_code -ne 0 ]]; then
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    die "Remote preflight failed for $CLUSTER."
  fi

  [[ -n "$output" && "$output" != *$'\n'* ]] || die "Remote preflight returned an invalid path."
  REMOTE_DIR="$output"
}

prepare_session_dirs() {
  # Private shared state for login and compute nodes.
  remote_bash "$SESSION_BASE" "$STATE_DIR" "$RUNTIME_BASE" "$LOG_DIR" <<'REMOTE'
set -Eeuo pipefail
umask 077
for path in "$1" "$2" "$3" "$4"; do
  mkdir -p -- "$path"
  chmod 700 -- "$path"
done
REMOTE
}

submit_job() {
  local export_values
  local output
  local exit_code
  local args

  # Send the job payload through stdin.
  export_values="ALL,JUPYTER_ROOT=$REMOTE_DIR,JUPYTER_SIF=$SIF_PATH,JUPYTER_STATE_DIR=$STATE_DIR,JUPYTER_RUNTIME_BASE=$RUNTIME_BASE,JUPYTER_LOG_DIR=$LOG_DIR"
  args=(
    sbatch
    --parsable
    "--job-name=$JOB_NAME"
    --nodes=1
    --ntasks=1
    "--cpus-per-task=$CPUS"
    "--mem=$MEMORY"
    "--time=$WALLTIME"
    "--partition=$PARTITION"
    "--account=$ACCOUNT"
    "--qos=$QOS"
    "--chdir=$REMOTE_DIR"
    "--output=$LOG_DIR/%j.log"
    --open-mode=append
    "--export=$export_values"
  )

  set +e
  output=$(remote_exec "${args[@]}" < "$JOB_SCRIPT")
  exit_code=$?
  set -e
  [[ $exit_code -eq 0 ]] || die "Slurm submission failed with code $exit_code."

  output=${output%%;*}
  [[ "$output" =~ ^[1-9][0-9]*$ ]] || die "Slurm returned an invalid Job ID."
  ACTIVE_JOB_ID="$output"
  ACTIVE_CLUSTER="$CLUSTER"
  field "Job ID" "$ACTIVE_JOB_ID"
}

job_identity() {
  remote_bash "$1" "$JOB_NAME" <<'REMOTE'
set -Eeuo pipefail

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

job_id="$1"
expected_name="$2"
user_name=$(id -un)
line=$(squeue -h -j "$job_id" -o '%u|%j|%T|%R' 2>/dev/null | head -n 1)
[[ -n "$line" ]] || exit 43
IFS='|' read -r owner job_name state reason <<< "$line"
owner=$(trim "$owner")
job_name=$(trim "$job_name")
state=$(trim "$state")
reason=$(trim "$reason")
[[ "$owner" == "$user_name" && "$job_name" == "$expected_name" ]] || exit 44
printf '%s|%s\n' "$state" "$reason"
REMOTE
}

safe_cancel() {
  local job_id="$1"
  local output
  local exit_code

  # Cancel only the expected owned job.
  set +e
  output=$(remote_bash "$job_id" "$JOB_NAME" <<'REMOTE'
set -Eeuo pipefail

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

job_id="$1"
expected_name="$2"
user_name=$(id -un)
line=$(squeue -h -j "$job_id" -o '%u|%j' 2>/dev/null | head -n 1)
[[ -n "$line" ]] || exit 43
IFS='|' read -r owner job_name <<< "$line"
owner=$(trim "$owner")
job_name=$(trim "$job_name")
[[ "$owner" == "$user_name" && "$job_name" == "$expected_name" ]] || exit 44
scancel "$job_id"
REMOTE
  )
  exit_code=$?
  set -e

  case $exit_code in
    0)
      status OK "Cancelled Slurm job $job_id."
      ;;
    43)
      status WARN "Slurm job $job_id is no longer active."
      ;;
    44)
      status ERROR "Refusing to cancel job $job_id: owner or job name mismatch."
      return 44
      ;;
    *)
      [[ -n "$output" ]] && printf '%s\n' "$output" >&2
      status ERROR "Could not cancel Slurm job $job_id."
      return "$exit_code"
      ;;
  esac
}

stop_tunnel() {
  if [[ -n "$TUNNEL_PID" ]] && kill -0 "$TUNNEL_PID" 2>/dev/null; then
    kill "$TUNNEL_PID" 2>/dev/null || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
  TUNNEL_PID=""
}

on_interrupt() {
  trap - INT
  printf '\n'
  status WARN "Ctrl-C received. Closing the tunnel and cancelling job $ACTIVE_JOB_ID."
  stop_tunnel
  if [[ -n "$ACTIVE_JOB_ID" && -n "$ACTIVE_CLUSTER" ]]; then
    safe_cancel "$ACTIVE_JOB_ID" || true
  fi
  exit 130
}

on_local_exit() {
  trap - HUP TERM
  stop_tunnel
  if [[ -n "$ACTIVE_JOB_ID" ]]; then
    status WARN "Local session ended. Slurm job $ACTIVE_JOB_ID was preserved."
    printf 'Reconnect with: run_jupyter connect %s %s\n' "$ACTIVE_CLUSTER" "$ACTIVE_JOB_ID"
  fi
  exit 143
}

read_state() {
  local job_id="$1"
  local state_path="$STATE_DIR/$job_id.state"
  local output
  local exit_code

  # State is parsed locally and never sourced.
  set +e
  output=$(remote_bash "$job_id" "$JOB_NAME" "$state_path" <<'REMOTE'
set -Eeuo pipefail

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

job_id="$1"
expected_name="$2"
state_path="$3"

user_name=$(id -un)
line=$(squeue -h -j "$job_id" -o '%u|%j|%T|%R' 2>/dev/null | head -n 1)
[[ -n "$line" ]] || exit 43
IFS='|' read -r owner job_name state reason <<< "$line"
owner=$(trim "$owner")
job_name=$(trim "$job_name")
state=$(trim "$state")
reason=$(trim "$reason")
[[ "$owner" == "$user_name" && "$job_name" == "$expected_name" ]] || exit 44

if [[ -r "$state_path" ]]; then
  cat -- "$state_path"
  exit 0
fi

printf 'waiting=%s|%s\n' "$state" "$reason"
exit 42
REMOTE
  )
  exit_code=$?
  set -e

  case $exit_code in
    0)
      STATE_TEXT="$output"
      return 0
      ;;
    42)
      WAIT_TEXT=${output#waiting=}
      return 42
      ;;
    43)
      die "Slurm job $job_id ended before Jupyter state became available. Private log: $LOG_DIR/$job_id.log"
      ;;
    44)
      die "Job $job_id is not your $JOB_NAME job."
      ;;
    *)
      status WARN "Cluster connection failed while waiting for job $job_id."
      printf 'Reconnect later with: run_jupyter connect %s %s\n' "$CLUSTER" "$job_id"
      exit "$exit_code"
      ;;
  esac
}

parse_state() {
  local text="$1"
  local key
  local value
  local version=""
  local node=""
  local port=""
  local token_b64=""

  while IFS='=' read -r key value; do
    case "$key" in
      version) [[ -z "$version" ]] || die "Duplicate version in Jupyter state."; version="$value" ;;
      node) [[ -z "$node" ]] || die "Duplicate node in Jupyter state."; node="$value" ;;
      port) [[ -z "$port" ]] || die "Duplicate port in Jupyter state."; port="$value" ;;
      token_b64) [[ -z "$token_b64" ]] || die "Duplicate token in Jupyter state."; token_b64="$value" ;;
      *) die "Unknown field in Jupyter state." ;;
    esac
  done <<< "$text"

  [[ "$version" == "1" ]] || die "Unsupported Jupyter state version."
  [[ "$node" =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid compute node in Jupyter state."
  [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] || die "Invalid remote port in Jupyter state."
  [[ "$token_b64" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || die "Invalid token encoding in Jupyter state."

  JUPYTER_NODE="$node"
  JUPYTER_PORT="$port"
  JUPYTER_TOKEN=$(printf '%s' "$token_b64" | base64 --decode) || die "Cannot decode the Jupyter token."
  [[ -n "$JUPYTER_TOKEN" && "$JUPYTER_TOKEN" != *$'\n'* && "$JUPYTER_TOKEN" != *$'\r'* ]] || die "Invalid Jupyter token."
}

wait_for_state() {
  local job_id="$1"
  local previous=""

  while true; do
    if read_state "$job_id"; then
      parse_state "$STATE_TEXT"
      return 0
    fi

    if [[ "$WAIT_TEXT" != "$previous" ]]; then
      status WAIT "Slurm: $WAIT_TEXT"
      previous="$WAIT_TEXT"
    fi
    sleep 5
  done
}

choose_local_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

open_browser() {
  local url="$1"
  cmd.exe /c start "" "$url" >/dev/null 2>&1
}

start_tunnel() {
  local local_port="$1"
  local forward="127.0.0.1:$local_port:$JUPYTER_NODE:$JUPYTER_PORT"

  # Expose Jupyter only on local loopback.
  ssh "${SSH_OPTIONS[@]}" \
    -o ExitOnForwardFailure=yes \
    -N -T -L "$forward" \
    "$CLUSTER" &
  TUNNEL_PID=$!
  sleep 1
  kill -0 "$TUNNEL_PID" 2>/dev/null
}

wait_for_http() {
  local url="$1"
  local attempt

  for attempt in $(seq 1 30); do
    if curl --fail --silent --show-error --location \
      --max-time 3 --output /dev/null "$url" 2>/dev/null; then
      return 0
    fi
    kill -0 "$TUNNEL_PID" 2>/dev/null || return 1
    sleep 1
  done
  return 1
}

session_failure() {
  local cancel_new_job="$1"
  local message="$2"

  stop_tunnel
  status ERROR "$message"
  if [[ "$cancel_new_job" == "true" ]]; then
    safe_cancel "$ACTIVE_JOB_ID" || true
  else
    status WARN "Slurm job $ACTIVE_JOB_ID was preserved."
    printf 'Retry with: run_jupyter connect %s %s\n' "$CLUSTER" "$ACTIVE_JOB_ID"
  fi
  exit 1
}

open_session() {
  local cancel_on_failure="$1"
  local local_port
  local url
  local tunnel_exit
  local identity
  local identity_code

  local_port=$(choose_local_port) || session_failure "$cancel_on_failure" "Cannot select a local port."
  field "Compute node" "$JUPYTER_NODE"
  field "Local port" "$local_port"

  if ! start_tunnel "$local_port"; then
    session_failure "$cancel_on_failure" "SSH tunnel could not reach the compute node."
  fi

  url="http://127.0.0.1:$local_port/lab?token=$JUPYTER_TOKEN"
  if ! wait_for_http "$url"; then
    session_failure "$cancel_on_failure" "JupyterLab did not answer through the SSH tunnel."
  fi
  if ! open_browser "$url"; then
    session_failure "$cancel_on_failure" "Windows could not open the default browser."
  fi

  status OK "JupyterLab opened in the Windows default browser."
  printf 'Keep this terminal open. Ctrl-C stops Jupyter and releases job %s.\n' "$ACTIVE_JOB_ID"

  set +e
  wait "$TUNNEL_PID"
  tunnel_exit=$?
  set -e
  TUNNEL_PID=""

  set +e
  identity=$(job_identity "$ACTIVE_JOB_ID")
  identity_code=$?
  set -e
  if [[ $identity_code -eq 43 ]]; then
    status OK "Slurm job $ACTIVE_JOB_ID ended."
    return
  fi

  status WARN "SSH tunnel ended with code $tunnel_exit. Slurm job $ACTIVE_JOB_ID was preserved."
  printf 'Reconnect with: run_jupyter connect %s %s\n' "$CLUSTER" "$ACTIVE_JOB_ID"
}

print_header() {
  printf '\n'
  color 36 "Cluster JupyterLab"
  printf '\n'
  field "Target" "$CLUSTER"
  field "Mode" "$ACTION"
  field "Rule" "Slurm compute node through a local SSH tunnel"
  field "Root" "$REMOTE_DIR"
  field "Container" "$SIF_PATH"
  field "Partition" "$PARTITION"
  field "Resources" "$CPUS CPU, $MEMORY, $WALLTIME"
  printf '\n'
}

run_start() {
  [[ $# -ge 1 ]] || die "start requires a cluster."
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    return
  fi
  select_cluster "$1"
  shift

  REMOTE_DIR="$REMOTE_ROOT"
  CPUS="$DEFAULT_CPUS"
  MEMORY="$DEFAULT_MEM"
  WALLTIME="$DEFAULT_TIME"

  if [[ $# -gt 0 && "$1" != --* ]]; then
    REMOTE_DIR="$1"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cpus)
        [[ $# -ge 2 ]] || die "--cpus requires a value."
        CPUS="$2"
        shift 2
        ;;
      --mem)
        [[ $# -ge 2 ]] || die "--mem requires a value."
        MEMORY="$2"
        shift 2
        ;;
      --time)
        [[ $# -ge 2 ]] || die "--time requires a value."
        WALLTIME="$2"
        shift 2
        ;;
      --partition)
        [[ $# -ge 2 ]] || die "--partition requires a value."
        PARTITION="$2"
        shift 2
        ;;
      -h|--help)
        usage
        return
        ;;
      *)
        die "Unknown start option: $1."
        ;;
    esac
  done

  # Real session lifecycle.
  validate_start_values
  require_local_start_tools
  remote_preflight || exit $?
  print_header
  prepare_session_dirs
  submit_job

  trap on_interrupt INT
  trap on_local_exit HUP TERM
  wait_for_state "$ACTIVE_JOB_ID"
  open_session true
  trap - INT HUP TERM
}

run_status() {
  [[ $# -ge 1 && $# -le 2 ]] || die "status requires a cluster and optional Job ID."
  select_cluster "$1"
  shift
  require_local_ssh

  if [[ $# -eq 0 ]]; then
    remote_bash "$JOB_NAME" <<'REMOTE'
set -Eeuo pipefail
job_name="$1"
user_name=$(id -un)
output=$(squeue -u "$user_name" -n "$job_name" -o '%.18i %.12P %.16j %.10T %.10M %.30R')
printf '%s\n' "$output"
REMOTE
    return
  fi

  validate_job_id "$1"
  local output
  local exit_code
  set +e
  output=$(job_identity "$1")
  exit_code=$?
  set -e
  case $exit_code in
    0) printf '%s\n' "$output" ;;
    43) die "Slurm job $1 is not active." ;;
    44) die "Job $1 is not your $JOB_NAME job." ;;
    *) die "Could not query Slurm job $1." ;;
  esac
}

run_connect() {
  [[ $# -eq 2 ]] || die "connect requires a cluster and Job ID."
  select_cluster "$1"
  validate_job_id "$2"
  require_local_start_tools

  ACTIVE_CLUSTER="$CLUSTER"
  ACTIVE_JOB_ID="$2"
  trap on_interrupt INT
  trap on_local_exit HUP TERM
  wait_for_state "$ACTIVE_JOB_ID"
  open_session false
  trap - INT HUP TERM
}

run_stop() {
  [[ $# -eq 2 ]] || die "stop requires a cluster and Job ID."
  select_cluster "$1"
  validate_job_id "$2"
  require_local_ssh
  safe_cancel "$2"
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

ACTION="$1"
shift

case "$ACTION" in
  start) run_start "$@" ;;
  status) run_status "$@" ;;
  connect) run_connect "$@" ;;
  stop) run_stop "$@" ;;
  *)
    status ERROR "Unknown action: $ACTION."
    usage >&2
    exit 1
    ;;
esac
