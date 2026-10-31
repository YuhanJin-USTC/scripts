#!/usr/bin/env bash

set -e
set -o pipefail
# Keep passphrases out of shell traces.
set +x

TARGET_USER="yuhanjin"
TARGET_HOME="/home/$TARGET_USER"
PROXY_URL="http://127.0.0.1:7890"
SOCKS_URL="socks5://127.0.0.1:7890"
PACMAN_FALLBACK_MIRROR='Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch'
SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
CURRENT_SET="$SCRIPT_DIR/data/github-current"
HELPER="$SCRIPT_DIR/backup_set.py"
PREVIEW=false
SET_DIR=""
LEGACY_DIR=""
CORE_ARCH_PACKAGES=(python-pynvim ipython python-matplotlib python-pylatexenc)
TOPIARY_NU_REVISION=18b7f951e0c511f854685dfcc9f6a34981101dd6
TOPIARY_NU_SHA256=6507a874e74108a380a043daefffc71ed3ead75beb46101df21f0792800cdad1

status() {
  if [ "$1" = ERROR ]; then printf '[%s] %s\n' "$1" "$2" >&2
  else printf '[%s] %s\n' "$1" "$2"; fi
}
field() { printf '%s: %s\n' "$1" "$2"; }
step() { printf '[%s] %s\n' "$1" "$2"; }
usage() {
  printf '%s\n' "Usage: $0 [--set PATH | --legacy PATH] [--preview]" "" \
    "Restore an explicitly selected Arch backup; real mode is the default." \
    "Without a path, interactively choose a complete set; never select newest automatically." "" \
    "Options:" "  --set PATH    Published data/github-current or a complete ID-named set." \
    "  --legacy PATH Old archlinux directory containing data/ and pkg_lists/." \
    "  --preview     Read public manifests only; no decryption, staging or changes." \
    "  -h, --help    Show this help." "" \
    "Examples:" "  bash backup/archlinux/restore.sh --preview" \
    "  sudo bash backup/archlinux/restore.sh --set /path/to/data/github-current"
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --preview) PREVIEW=true; shift ;;
    --set|--legacy)
      [ "$#" -ge 2 ] && [[ "$2" != --* ]] || { status ERROR "$1 requires a path."; exit 2; }
      [ -z "$SET_DIR$LEGACY_DIR" ] || { status ERROR 'Choose exactly one backup source.'; exit 2; }
      if [ "$1" = --set ]; then SET_DIR=$(realpath -m "$2"); else LEGACY_DIR=$(realpath -m "$2"); fi
      shift 2 ;;
    *) status ERROR "Unknown argument: $1."; usage >&2; exit 2 ;;
  esac
done
printf '\nArch Linux WSL restore\n'
field Target "$TARGET_HOME, selected /etc files and /usr/local/bin/topiary"
field Mode "$([ "$PREVIEW" = true ] && printf preview || printf run)"
field Rule 'validate all payloads first; review differences; preserve before deployment'
field Privileges 'new target user: wheel membership and NOPASSWD: ALL'
field 'Editor core' "${CORE_ARCH_PACKAGES[*]}; system provider/IPython before Neovim validation"
field 'Base packages' 'base-devel git stow sudo tar openssh gnupg python bubblewrap'
field Packages 'Pacman system upgrade/install and AUR install; observed old versions are a rebuild record, not a downgrade promise'
field Repositories 'restore selected worktree contents; retain existing .git and old backup payloads; no fetch/reset/clean'
field Proxy "AUR HTTP=$PROXY_URL SOCKS=$SOCKS_URL; package fallback=https://geo.mirror.pkgbuild.com"
field 'AUR bootstrap' 'if yay is missing: https://aur.archlinux.org/yay-bin.git, new private build directory, target-user makepkg; explicit confirmation before network/build/install'
if [ -z "$SET_DIR$LEGACY_DIR" ]; then
  candidates=()
  if [ -f "$CURRENT_SET/COMPLETE" ]; then candidates+=("$CURRENT_SET/COMPLETE"); fi
  if [ "${#candidates[@]}" -eq 0 ]; then
    if [ "$PREVIEW" = true ]; then status DRY-RUN 'No complete set found; select --set PATH or --legacy PATH before recovery.'; exit 0; fi
    status ERROR 'No complete backup sets found.'; exit 1
  fi
  for index in "${!candidates[@]}"; do printf '[%s] %s\n' "$((index + 1))" "${candidates[index]%/COMPLETE}"; done
  if [ "$PREVIEW" = true ]; then status DRY-RUN 'No set selected; no decryption, staging or writes.'; exit 0; fi
  [ -t 0 ] || { status ERROR 'Choose --set PATH in non-interactive invocation.'; exit 2; }
  read -r -p 'Choose a backup set number: ' selection
  [[ "$selection" =~ ^[1-9][0-9]*$ ]] && [ "$selection" -le "${#candidates[@]}" ] || { status ERROR 'Invalid set number.'; exit 2; }
  SET_DIR=${candidates[selection-1]%/COMPLETE}
fi
field Source "${SET_DIR:-$LEGACY_DIR}"
if [ "$PREVIEW" = true ]; then
  if [ -n "$SET_DIR" ]; then
    python3 -B "$HELPER" verify "$SET_DIR" >/dev/null
    status DRY-RUN 'Public hashes and archive structure verified; encrypted members, actual differences and deployment remain unchecked.'
  else status WARN 'Legacy payloads cannot prove same-batch consistency; no complete-set success will be reported.'; fi
  status DRY-RUN 'No credential access, decryption, package operations or target writes.'
  exit 0
fi
[ "$EUID" -eq 0 ] || { status ERROR 'Run real recovery as root.'; exit 1; }
[ -t 0 ] || { status ERROR 'Recovery requires a terminal for exact differences and confirmations.'; exit 1; }

# Run from a private copy before restoring the scripts worktree.
IS_RUNNER=false
if [[ "$SCRIPT_DIR" =~ ^/tmp/arch-restore-runner\.[A-Za-z0-9_]{8}$ ]] &&
  [ "${ARCH_RESTORE_STAGE:-}" = "$SCRIPT_DIR" ] &&
  [ "$(readlink "/proc/$$/fd/9" 2>/dev/null || true)" = "$SCRIPT_DIR/.owned" ]; then
  IS_RUNNER=true
fi
if [ "$IS_RUNNER" = false ]; then
  command -v python3 >/dev/null || { status ERROR 'Python is required for preflight and safe staging.'; exit 1; }
  runner=""; runner_id=""
  IFS=$'\t' read -r runner runner_id < <(python3 -B "$HELPER" temp-create arch-restore-runner.)
  trap 'CODEX_TEMP_CLEANUP=1 python3 -B "$HELPER" cleanup "$runner" "$runner_id"' EXIT
  : >"$runner/.owned"
  chmod 600 "$runner/.owned"
  exec 9<>"$runner/.owned"
  cp -- "$SCRIPT_DIR/restore.sh" "$SCRIPT_DIR/backup_set.py" "$SCRIPT_DIR/nvim_state.py" \
    "$SCRIPT_DIR/nvim_plugins.lua" "$SCRIPT_DIR/rayfile_state.py" "$SCRIPT_DIR/mason_tools.py" \
    "$SCRIPT_DIR/topiary_dependencies.py" "$runner/"
  export ARCH_RESTORE_STAGE="$runner"
  if [ -n "$SET_DIR" ]; then exec bash "$runner/restore.sh" --set "$SET_DIR"
  else exec bash "$runner/restore.sh" --legacy "$LEGACY_DIR"; fi
fi
umask 077
unset GPG_PASS
WORK_DIR=""
GPG_HOME=""
GPG_ID=""
GPG_SOCKET_DIR=""
GPG_SOCKET_ID=""
GPG_SOCKET=""
GPG_AGENT_PID=""
GPG_STARTED=false
USER_STAGE=""
YAY_BUILD_DIR=""
YAY_BUILD_ID=""
RESTORE_BACKUP_DIR=""
CURRENT_COMPONENT="preflight"
RESTORE_OUTCOME="running"
STOW_ROLLBACK_PENDING=false
STOW_MOVED_TARGETS=()
STOW_MOVED_BACKUPS=()
CREDENTIAL_EXCLUDES=()
CLEANUP_PATHS=("$SCRIPT_DIR")
CLEANUP_IDS=("$(python3 -B "$HELPER" temp-id "$SCRIPT_DIR")")
RESULT_ORDER=(preflight packages system home credentials scripts dot_files research_workflow topiary nvim rayfile rebuild jukit_core mason_tools formatter_linter_tools private_npm cleanup)
declare -A RESULT_STATE=() RESULT_DETAIL=()
for component in "${RESULT_ORDER[@]}"; do
  RESULT_STATE[$component]=unverified
  RESULT_DETAIL[$component]='No completed operation yet.'
done
set_result() {
  RESULT_STATE[$1]=$2
  RESULT_DETAIL[$1]=$3
  if [ "$CURRENT_COMPONENT" = "$1" ] && [[ "$2" = verified || "$2" = skipped || "$2" = uncovered ]]; then CURRENT_COMPONENT=""; fi
}
make_temp() {
  local variable=$1 prefix=$2 path identity
  case "$variable" in WORK_DIR|USER_STAGE) ;; *) return 1 ;; esac
  IFS=$'\t' read -r path identity < <(python3 -B "$HELPER" temp-create "$prefix")
  CLEANUP_PATHS+=("$path"); CLEANUP_IDS+=("$identity")
  printf -v "$variable" '%s' "$path"
}
ensure_crypto_home() {
  if [ -z "$GPG_HOME" ]; then
    GPG_HOME="$WORK_DIR/gpg-home"
    mkdir -m 700 -- "$GPG_HOME"
    GPG_ID=$(python3 -B "$HELPER" temp-id "$GPG_HOME")
    python3 -B - "$WORK_DIR/gpg-socket-before.json" <<'PY_GPG_BEFORE'
from pathlib import Path
import json,os,stat,sys
parent=Path('/run/user')/str(os.geteuid())/'gnupg'
for path in (parent,*parent.parents):
 if path.is_symlink() or path.exists() and not path.is_dir():raise SystemExit('Unsafe GPG runtime parent.')
info=parent.stat() if parent.exists() else None
value={'parent':str(parent),'existed':info is not None,'identity':[info.st_dev,info.st_ino] if info else None,'children':[p.name for p in parent.iterdir()] if info else []}
Path(sys.argv[1]).write_text(json.dumps(value)+'\n')
PY_GPG_BEFORE
    GPG_SOCKET_DIR=$(gpgconf --homedir "$GPG_HOME" --list-dirs socketdir)
    GPG_SOCKET=$(gpgconf --homedir "$GPG_HOME" --list-dirs agent-socket)
    python3 -B - "$GPG_HOME" "$GPG_SOCKET_DIR" "$GPG_SOCKET" "$WORK_DIR/gpg-socket-before.json" <<'PY_GPG_PATH'
from pathlib import Path
import json,os,stat,sys
home,directory,socket=map(Path,sys.argv[1:4]);record=Path(sys.argv[4]);before=json.loads(record.read_text())
if not all(path.is_absolute() and '..' not in path.parts for path in (home,directory,socket)):raise SystemExit('Invalid private GPG socket path.')
if socket.parent!=directory:raise SystemExit('GPG socket and private directory disagree.')
if directory!=home:
 parent=directory.parent
 if parent!=Path(before['parent']) or not directory.name.startswith('d.'):raise SystemExit('Refusing a shared GPG socket directory.')
 if directory.name in before['children']:raise SystemExit('Private GPG socket directory existed before this invocation.')
 for path in (parent,directory):
  info=path.lstat()
  if not stat.S_ISDIR(info.st_mode) or info.st_uid!=os.geteuid() or stat.S_IMODE(info.st_mode)!=0o700:raise SystemExit('Unsafe private GPG socket directory.')
 info=parent.stat();identity=[info.st_dev,info.st_ino]
 if before['existed'] and before['identity']!=identity:raise SystemExit('GPG runtime parent changed during setup.')
 if any(directory.iterdir()):raise SystemExit('Private GPG socket directory is not empty before startup.')
 before['created_parent_identity']=identity if not before['existed'] else None
 record.write_text(json.dumps(before)+'\n')
PY_GPG_PATH
    if [ "$GPG_SOCKET_DIR" != "$GPG_HOME" ]; then GPG_SOCKET_ID=$(python3 -B "$HELPER" temp-id "$GPG_SOCKET_DIR"); fi
  fi
  python3 -B "$HELPER" check-temp "$GPG_HOME" "$GPG_ID"
  GPG_STARTED=true
}
record_crypto_runtime() {
  local socket_dir agent_socket
  socket_dir=$(gpgconf --homedir "$GPG_HOME" --list-dirs socketdir) || return 1
  agent_socket=$(gpgconf --homedir "$GPG_HOME" --list-dirs agent-socket) || return 1
  [ "$socket_dir" = "$GPG_SOCKET_DIR" ] && [ "$agent_socket" = "$GPG_SOCKET" ] || { status ERROR 'Private GPG socket routing changed.'; return 1; }
  if [ "$GPG_SOCKET_DIR" != "$GPG_HOME" ] && [ -d "$GPG_SOCKET_DIR" ]; then
    if [ -z "$GPG_SOCKET_ID" ]; then GPG_SOCKET_ID=$(python3 -B "$HELPER" temp-id "$GPG_SOCKET_DIR") || return 1
    else python3 -B "$HELPER" check-temp "$GPG_SOCKET_DIR" "$GPG_SOCKET_ID" || return 1; fi
  fi
  if gpg-connect-agent --homedir "$GPG_HOME" --no-autostart 'GETINFO pid' /bye >"$WORK_DIR/crypto-agent.info" 2>"$WORK_DIR/crypto-agent.err"; then
    GPG_AGENT_PID=$(python3 -B - "$WORK_DIR/crypto-agent.info" <<'PY_GPG_PID'
from pathlib import Path
import re,sys
values=re.findall(r'^D ([0-9]+)$',Path(sys.argv[1]).read_text(),re.M)
if len(values)!=1:raise SystemExit('Could not identify the private GPG agent.')
print(values[0])
PY_GPG_PID
) || return 1
  elif [ -e "$GPG_SOCKET" ] || [ -L "$GPG_SOCKET" ]; then
    status ERROR 'Private GPG socket exists but its agent could not be identified.'
    return 1
  fi
  python3 -B - "$WORK_DIR/crypto-runtime.json" "$GPG_HOME" "$GPG_ID" "$GPG_SOCKET_DIR" "$GPG_SOCKET_ID" "$GPG_SOCKET" "$GPG_AGENT_PID" <<'PY_GPG_RECORD'
from pathlib import Path
import json,sys
Path(sys.argv[1]).write_text(json.dumps(dict(zip(('home','home_identity','socket_directory','socket_identity','agent_socket','agent_pid'),sys.argv[2:])))+'\n')
PY_GPG_RECORD
}
stop_crypto_agent() {
  if [ "$GPG_STARTED" = true ]; then
    python3 -B "$HELPER" check-temp "$GPG_HOME" "$GPG_ID" || return 1
    record_crypto_runtime || return 1
    gpgconf --homedir "$GPG_HOME" --kill gpg-agent || return 1
    python3 -B - "$GPG_AGENT_PID" <<'PY_GPG_EXIT' || return 1
from pathlib import Path
import sys,time
if not sys.argv[1]:raise SystemExit(0)
path=Path('/proc')/sys.argv[1]/'stat'
for _ in range(40):
 try:
  value=path.read_text();state=value[value.rfind(')')+2:].split()[0]
  if state=='Z':break
 except FileNotFoundError:break
 time.sleep(0.05)
else:raise SystemExit('Private GPG agent did not exit after its scoped shutdown.')
PY_GPG_EXIT
    if [ "$GPG_SOCKET_DIR" != "$GPG_HOME" ] && [ -d "$GPG_SOCKET_DIR" ]; then
      python3 -B "$HELPER" check-temp "$GPG_SOCKET_DIR" "$GPG_SOCKET_ID" || return 1
      CODEX_TEMP_CLEANUP=1 gpgconf --homedir "$GPG_HOME" --remove-socketdir || return 1
      [ ! -e "$GPG_SOCKET_DIR" ] || { status ERROR "Private GPG socket directory retained: $GPG_SOCKET_DIR"; return 1; }
    fi
    python3 -B - "$WORK_DIR/gpg-socket-before.json" <<'PY_GPG_PARENT' || return 1
from pathlib import Path
import json,os,stat,sys
value=json.loads(Path(sys.argv[1]).read_text());identity=value.get('created_parent_identity')
if identity:
 parent=Path(value['parent'])
 if parent.exists():
  info=parent.lstat()
  if not stat.S_ISDIR(info.st_mode) or info.st_uid!=os.geteuid() or [info.st_dev,info.st_ino]!=identity:raise SystemExit('GPG runtime parent identity changed; retained.')
  if not any(parent.iterdir()):
   os.environ['CODEX_TEMP_CLEANUP']='1';parent.rmdir()
PY_GPG_PARENT
    GPG_STARTED=false
  fi
}
cleanup_restore_tmp() {
  local index failed=0 keep_work=false
  unset GPG_PASS
  if ! stop_crypto_agent; then
    status ERROR "Isolated GPG cleanup failed; private staging retained: $WORK_DIR"
    failed=1
    keep_work=true
  fi
  for ((index=${#CLEANUP_PATHS[@]}-1; index>=0; index--)); do
    if [ "$keep_work" = true ] && [ "${CLEANUP_PATHS[index]}" = "$WORK_DIR" ]; then continue; fi
    if ! CODEX_TEMP_CLEANUP=1 python3 -B "$HELPER" cleanup "${CLEANUP_PATHS[index]}" "${CLEANUP_IDS[index]}"; then
      status ERROR "Temporary cleanup refused or failed: ${CLEANUP_PATHS[index]}"
      failed=1
    fi
  done
  return "$failed"
}
report_restore() {
  local component
  printf '\nComponent results\n'
  for component in "${RESULT_ORDER[@]}"; do
    printf '%-20s %-10s %s\n' "$component" "${RESULT_STATE[$component]}" "${RESULT_DETAIL[$component]}"
  done
}
finish_restore() {
  local code=$?
  set +e
  if [ "$STOW_ROLLBACK_PENDING" = true ]; then rollback_stow; fi
  if [ "$code" -ne 0 ] && [ "$RESTORE_OUTCOME" != legacy ] && [ -n "$CURRENT_COMPONENT" ]; then
    set_result "$CURRENT_COMPONENT" failed "Operation stopped with exit $code; see the preceding error."
  fi
  if cleanup_restore_tmp; then
    set_result cleanup verified 'Invocation-owned temporary paths removed and isolated GPG agent stopped.'
  else
    set_result cleanup failed 'Cleanup was stopped safely; see the exact retained temporary paths above.'
    [ "$code" -ne 0 ] || code=1
  fi
  report_restore
  if [ -n "$RESTORE_BACKUP_DIR" ] && [ -d "$RESTORE_BACKUP_DIR" ]; then
    report_restore >"$RESTORE_BACKUP_DIR/component-results.txt"
  fi
  exit "$code"
}
trap finish_restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
for command in python3 tar gpg gpgconf gpg-connect-agent pacman; do
  command -v "$command" >/dev/null || { status ERROR "Preflight dependency missing: $command."; exit 1; }
done
make_temp WORK_DIR arch-restore-payload.
confirm() {
  local answer
  printf '%s\n' "$1"
  read -r -p 'Type yes to continue: ' answer </dev/tty
  [ "$answer" = yes ] || { status ERROR 'Recovery stopped; existing safety backups are retained.'; exit 1; }
}
NVIM_READY=false
RAYFILE_READY=false
RECOVERY_ID=legacy

step 1/8 'Verify every archive, encrypted internal manifest, architecture and staging space.'
if [ -n "$SET_DIR" ]; then
  python3 -B "$HELPER" verify "$SET_DIR" >"$WORK_DIR/set.json"
  RECOVERY_ID=$(python3 -B -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$WORK_DIR/set.json")
  python3 -B - "$WORK_DIR/set.json" "$WORK_DIR/components" "$WORK_DIR/component-states" <<'PY'
import json,sys
from pathlib import Path
value=json.loads(Path(sys.argv[1]).read_text())
with Path(sys.argv[2]).open('w') as out:
 for name,row in value['components'].items():
  if row['state']=='present':out.write(name+'\t'+row['file']+'\n')
with Path(sys.argv[3]).open('w') as out:
 for name,row in value['components'].items():
  reason='Payload selected; not yet staged.' if row['state']=='present' else row['reason']
  reason=''.join(c if ord(c)>=32 else ' ' for c in reason)
  out.write(name+'\t'+('unverified' if row['state']=='present' else 'skipped')+'\t'+reason+'\n')
PY
  while IFS=$'\t' read -r name state reason; do set_result "$name" "$state" "$reason"; done <"$WORK_DIR/component-states"
  while IFS=$'\t' read -r name filename; do
    cp -- "$SET_DIR/$filename" "$WORK_DIR/$filename"
  done <"$WORK_DIR/components"
  python3 -B - "$WORK_DIR/set.json" "$WORK_DIR" <<'PY_COPY'
import hashlib,json,sys
from pathlib import Path
value=json.loads(Path(sys.argv[1]).read_text());root=Path(sys.argv[2])
for row in value['components'].values():
 if row['state']=='present':
  with (root/row['file']).open('rb') as stream:
   if hashlib.file_digest(stream,'sha256').hexdigest()!=row['sha256']:raise SystemExit('Copied payload changed.')
PY_COPY
  while IFS=$'\t' read -r name filename; do
    CURRENT_COMPONENT="$name"
    archive="$WORK_DIR/$filename"
    if [[ "$filename" == *.gpg ]]; then
      [ -n "${GPG_PASS:-}" ] || { read -r -s -p 'Backup GPG passphrase: ' GPG_PASS </dev/tty; printf '\n'; }
      archive="$WORK_DIR/$name.tar.gz"
      ensure_crypto_home
      printf '%s\n' "$GPG_PASS" | gpg --homedir "$GPG_HOME" --no-options --no-symkey-cache --batch --pinentry-mode loopback --passphrase-fd 0 \
        --decrypt --output "$archive" "$WORK_DIR/$filename"
      chmod 600 "$archive"
    fi
    case "$name" in
      nvim)
        python3 -B "$SCRIPT_DIR/nvim_state.py" --home "$TARGET_HOME" stage "$archive" "$WORK_DIR/nvim" --json >"$WORK_DIR/nvim-stage.json"
        python3 -B -c 'import json,sys; v=json.load(open(sys.argv[1])); assert v["status"]=="ready" and v["format"]==2' "$WORK_DIR/nvim-stage.json"
        NVIM_READY=true ;;
      rayfile)
        mkdir "$WORK_DIR/rayfile"
        python3 -B "$SCRIPT_DIR/rayfile_state.py" stage "$archive" "$WORK_DIR/rayfile"
        RAYFILE_READY=true ;;
      *) python3 -B "$HELPER" stage "$archive" "$WORK_DIR/$name" --require-catalog >/dev/null ;;
    esac
    set_result "$name" unverified 'Archive structure, architecture and available hashes checked; deployment pending.'
  done <"$WORK_DIR/components"
  unset GPG_PASS
  python3 -B "$WORK_DIR/research_workflow/tools/researchctl.py" --workspace "$WORK_DIR/no-device.toml" \
    doctor --compatibility-only --store "$WORK_DIR/research_workflow/metadata/STORE.json" --json
else
  status WARN 'Legacy recovery cannot establish batch consistency; optional missing components remain missing.'
  for component in packages system home credentials scripts dot_files research_workflow topiary nvim rayfile rebuild; do
    set_result "$component" skipped 'Not present in the selected legacy layout.'
  done
  for pair in system:sys_config home:home_config; do
    name=${pair%:*}; file=${pair#*:}
    if [ -f "$LEGACY_DIR/data/$file.tar.gz" ]; then
      CURRENT_COMPONENT="$name"
      python3 -B "$HELPER" stage "$LEGACY_DIR/data/$file.tar.gz" "$WORK_DIR/$name" >/dev/null
      set_result "$name" unverified 'Legacy archive checked; same-batch consistency unproven.'
    fi
  done
  CURRENT_COMPONENT=packages
  set_result packages unverified 'Legacy package lists selected; exact historical versions may be unavailable.'
  mkdir "$WORK_DIR/packages"
  for name in pkglist-pacman.txt pkglist-aur.txt; do
    [ -f "$LEGACY_DIR/pkg_lists/$name" ] && [ ! -L "$LEGACY_DIR/pkg_lists/$name" ] || { status ERROR "Missing legacy package list: $name"; exit 1; }
    cp -- "$LEGACY_DIR/pkg_lists/$name" "$WORK_DIR/packages/$name"
  done
  if [ -f "$LEGACY_DIR/data/default_shell.txt" ]; then cp -- "$LEGACY_DIR/data/default_shell.txt" "$WORK_DIR/packages/"; fi
  if [ -f "$LEGACY_DIR/data/secure_data.tar.gz.gpg" ]; then
    CURRENT_COMPONENT=credentials
    set_result credentials unverified 'Legacy encrypted credentials selected.'
    ensure_crypto_home
    read -r -s -p 'Legacy GPG passphrase: ' GPG_PASS </dev/tty; printf '\n'
    printf '%s\n' "$GPG_PASS" | gpg --homedir "$GPG_HOME" --no-options --no-symkey-cache --batch --pinentry-mode loopback --passphrase-fd 0 \
      --decrypt --output "$WORK_DIR/credentials.tar.gz" "$LEGACY_DIR/data/secure_data.tar.gz.gpg"
    unset GPG_PASS
    python3 -B "$HELPER" stage "$WORK_DIR/credentials.tar.gz" "$WORK_DIR/credentials" >/dev/null
  fi
  if [ -f "$LEGACY_DIR/data/nvim.tar.gz" ]; then
    CURRENT_COMPONENT=nvim
    set_result nvim unverified 'Legacy editor archive selected.'
    stage_exit=0
    python3 -B "$SCRIPT_DIR/nvim_state.py" --home "$TARGET_HOME" stage "$LEGACY_DIR/data/nvim.tar.gz" "$WORK_DIR/nvim" --json >"$WORK_DIR/nvim-stage.json" 2>"$WORK_DIR/nvim-stage.err" || stage_exit=$?
    if [ "$stage_exit" -eq 0 ]; then
      python3 -B -c 'import json,sys; v=json.load(open(sys.argv[1])); assert v["status"]=="ready" and v["format"]==2' "$WORK_DIR/nvim-stage.json"
      NVIM_READY=true
    elif [ "$stage_exit" -eq 3 ]; then
      python3 -B -c 'import json,sys; v=json.load(open(sys.argv[1])); assert v["status"]=="needs-rebuild" and v["format"]==1' "$WORK_DIR/nvim-stage.json"
      status WARN 'Legacy Neovim needs rebuilding; it will not be activated.'
      set_result nvim uncovered 'Format 1 lacks plugin/native contents; no activation.'
    else
      cat "$WORK_DIR/nvim-stage.err" >&2
      status ERROR 'Legacy Neovim archive failed preflight.'
      exit 1
    fi
  fi
  if [ -f "$LEGACY_DIR/data/rayfile.tar.gz" ]; then
    CURRENT_COMPONENT=rayfile
    set_result rayfile unverified 'Legacy managed-client archive selected.'
    mkdir "$WORK_DIR/rayfile"
    python3 -B "$SCRIPT_DIR/rayfile_state.py" stage "$LEGACY_DIR/data/rayfile.tar.gz" "$WORK_DIR/rayfile"
    RAYFILE_READY=true
  fi
fi

# Validate package input before the first privileged change.
python3 -B - "$WORK_DIR/packages" "$SET_DIR" <<'PY'
from pathlib import Path
import re,sys
root=Path(sys.argv[1])
if sys.argv[2]:
 for name in ('versions.txt','default_shell.txt','jukit-core-versions.txt'):
  if not (root/name).is_file() or (root/name).is_symlink():raise SystemExit('Missing package/version/shell evidence.')
if (root/'default_shell.txt').exists():
 value=(root/'default_shell.txt').read_text().splitlines()
 if len(value)!=1 or not value[0].startswith('/') or any(ord(c)<32 for c in value[0]):raise SystemExit('Invalid default-shell record.')
for name in ('pkglist-pacman.txt','pkglist-aur.txt'):

 values=(root/name).read_text().splitlines()
 if any(not re.fullmatch(r'[a-zA-Z0-9@_+][a-zA-Z0-9@_.+:-]*',v) for v in values):raise SystemExit('Invalid package-list entry.')
 if len(values)!=len(set(values)):raise SystemExit('Duplicate package-list entry.')
PY
mapfile -t AUR_PACKAGES <"$WORK_DIR/packages/pkglist-aur.txt"
mapfile -t PACMAN_PACKAGES <"$WORK_DIR/packages/pkglist-pacman.txt"
if [ "${#AUR_PACKAGES[@]}" -gt 0 ] && ! command -v yay >/dev/null; then
  status WARN 'yay is missing; the explicit AUR bootstrap stage will require network/build/install confirmation.'
fi

# Reject targets or payloads outside the selected component scope.
python3 -B - "$WORK_DIR" "$TARGET_HOME" "$TOPIARY_NU_REVISION" "$TOPIARY_NU_SHA256" <<'PY'
from pathlib import Path
import os,shutil,sys
root=Path(sys.argv[1]);home=Path(sys.argv[2])
allowed={'system':{'etc/pacman.conf','etc/pacman.d/mirrorlist','etc/makepkg.conf','etc/wsl.conf','etc/locale.conf','etc/fstab'},
'home':{'.bashrc','.bash_profile','.bash_logout','AGENTS.md'}}
for name,paths in allowed.items():
 base=root/name
 if base.exists():
  for path in base.rglob('*'):
   if path.relative_to(base).as_posix()=='.backup-manifest.json':continue
   if not path.is_dir() and path.relative_to(base).as_posix() not in paths:raise SystemExit('Unexpected selected-config member.')
if home.is_symlink():raise SystemExit('Target home cannot be a symlink.')
base=root/'credentials'
if base.exists():
 for path in base.rglob('*'):
  rel=path.relative_to(base).as_posix()
  if path.is_dir() or rel=='.backup-manifest.json':continue
  if rel=='.ssh/config' or not (rel.startswith('.ssh/') or rel.startswith('.gnupg/') or rel in ('.gitconfig','.codex/.env','.config/rclone/rclone.conf')):raise SystemExit('Unexpected credential member.')
for name in ('scripts','dot_files','research_workflow'):
 base=root/name
 for path in base.rglob('*') if base.exists() else []:
  if '.git' in path.parts:raise SystemExit('Git metadata unexpectedly included.')
 for blocked in ('.git', '.codex', '.agents'):
  if (base/blocked).exists() or (base/blocked).is_symlink():raise SystemExit('Unexpected worktree state in archive.')
for rel in ('scripts/backup/archlinux/data','scripts/backup/archlinux/pkg_lists','research_workflow/workspace.toml','research_workflow/.research-workflow'):
 if (root/rel).exists() or (root/rel).is_symlink():raise SystemExit('Local/backup state unexpectedly included.')
if (root/'topiary').exists():
 import hashlib,json,re,stat
 base=root/'topiary';value=json.loads((base/'runtime.json').read_text());binary=base/'bin/topiary'
 if value.get('format')!=2 or value['executable']['path']!='/usr/local/bin/topiary':raise SystemExit('Unsupported Topiary original-path record.')
 if not binary.is_file() or binary.is_symlink() or not os.access(binary,os.X_OK):raise SystemExit('Invalid Topiary executable.')
 if hashlib.sha256(binary.read_bytes()).hexdigest()!=value['executable']['sha256'] or stat.S_IMODE(binary.stat().st_mode)!=value['executable']['mode']:raise SystemExit('Topiary executable metadata mismatch.')
 grammar=value.get('grammar',{});artifact=base/'grammar/nu.so';revision,expected=sys.argv[3:5]
 if grammar.get('language')!='nu' or grammar.get('repository')!='https://github.com/nushell/tree-sitter-nu.git' or grammar.get('revision')!=revision or grammar.get('cache_path')!=f'.cache/topiary/nu/{revision}/grammar.so' or grammar.get('tree_sitter_language_abi')!=15:raise SystemExit('Unsupported Topiary Nu grammar source/path record.')
 if not artifact.is_file() or artifact.is_symlink() or grammar.get('sha256')!=expected or hashlib.sha256(artifact.read_bytes()).hexdigest()!=expected or stat.S_IMODE(artifact.stat().st_mode)!=grammar.get('mode'):raise SystemExit('Topiary Nu grammar artifact differs from its accepted record.')
 rows=value['dependencies']
 if not rows or sum(row['role']=='loader' for row in rows)!=1 or len({row['name'] for row in rows})!=len(rows):raise SystemExit('Invalid Topiary dependencies.')
 for row in rows:
  if not re.fullmatch(r'[A-Za-z0-9_.+-]+',row['name']) or row['role'] not in ('library','loader'):raise SystemExit('Invalid Topiary dependency identity.')
  for key in ('path','realpath'):
   path=Path(row[key])
   if not path.is_absolute() or '..' in path.parts or not str(path).startswith(('/usr/lib/','/lib/','/lib64/')):raise SystemExit('Unsupported Topiary system-library path.')
  if not re.fullmatch(r'[0-9a-f]{64}',row['sha256']):raise SystemExit('Invalid Topiary dependency hash.')
  source=row['source']
  if source.get('manager')=='pacman' and not re.fullmatch(r'[a-z0-9][a-z0-9@._+:-]*',source.get('package','')):raise SystemExit('Invalid Topiary package source.')
  if source.get('manager') not in ('pacman','unknown'):raise SystemExit('Unknown Topiary source manager.')
 for path in base.rglob('*'):
  if not path.is_dir() and path.relative_to(base).as_posix() not in ('.backup-manifest.json','runtime.json','dependencies.txt','version.txt','bin/topiary','grammar/nu.so'):raise SystemExit('Unexpected Topiary runtime payload.')
needed=sum(p.stat().st_size for p in root.rglob('*') if p.is_file() and not p.is_symlink())*2
for destination in (Path('/'),home):
 while not destination.exists():destination=destination.parent
 if shutil.disk_usage(destination).free<needed+256*1024*1024:raise SystemExit('Insufficient recovery destination space.')
PY
TOPIARY_PACKAGES=()
if [ -d "$WORK_DIR/topiary" ]; then
  python3 -B "$HELPER" parents "$TARGET_HOME/.cache/topiary/nu/$TOPIARY_NU_REVISION"
  python3 -B - "$WORK_DIR/topiary/runtime.json" >"$WORK_DIR/topiary-packages.txt" <<'PY_TOPIARY_PACKAGES'
import json,sys
value=json.load(open(sys.argv[1]))
for package in sorted({row['source']['package'] for row in value['dependencies'] if row['source']['manager']=='pacman' and row['source'].get('official_repository') is True and row['source'].get('repository') in ('core','extra','multilib')}):print(package)
PY_TOPIARY_PACKAGES
  mapfile -t TOPIARY_PACKAGES <"$WORK_DIR/topiary-packages.txt"
fi
FORMATTER_PACKAGES=()
if [ -f "$WORK_DIR/rebuild/editor_tools.json" ]; then
  python3 -B - "$WORK_DIR/rebuild/editor_tools.json" "$WORK_DIR/formatter-packages.txt" <<'PY_FORMATTER_PACKAGES'
from pathlib import Path
import json,re,sys
records=json.load(open(sys.argv[1])).get('formatter_linter_tools')
packages=set()
if records is None:print('[WARN] No six-tool formatter/linter reconstruction records; recovery remains uncovered.')
else:
 if records.get('format')!=1 or set(records.get('tools',{}))!={'isort','black','shfmt','markdownlint','clang-tidy','pylint'}:raise SystemExit('Invalid formatter/linter reconstruction records.')
 for name,row in records['tools'].items():
  source=row['source'];rebuild=row['rebuild'];method=rebuild.get('method')
  if method=='existing-arch-package-transaction':
   package=source.get('package','')
   if source.get('manager')!='pacman' or source.get('official_repository') is not True or source.get('repository') not in ('core','extra','multilib') or not re.fullmatch(r'[a-z0-9][a-z0-9@._+:-]*',package) or rebuild.get('packages')!=[package]:raise SystemExit('Unsupported formatter/linter Arch package source.')
   packages.add(package)
  elif method=='existing-mason-record':
   if source.get('manager')!='mason' or source.get('package') not in ('clangd','python-lsp-server','clang-format','stylua'):raise SystemExit('Unsupported formatter/linter Mason source.')
  elif method!='unavailable':raise SystemExit('Unknown formatter/linter reconstruction method.')
  print(f"[TOOL] {name}: {row.get('path')} -> {source.get('package','unknown')} {source.get('package_version','unknown')}; {method}")
Path(sys.argv[2]).write_text(''.join(package+'\n' for package in sorted(packages)))
PY_FORMATTER_PACKAGES
  mapfile -t FORMATTER_PACKAGES <"$WORK_DIR/formatter-packages.txt"
fi
if [ "$NVIM_READY" = true ]; then
  CURRENT_COMPONENT=mason_tools
  [ -f "$WORK_DIR/rebuild/editor_tools.json" ] || { status ERROR 'Missing exact editor-tool reconstruction records.'; exit 1; }
  python3 -B "$SCRIPT_DIR/nvim_state.py" --home "$TARGET_HOME" \
    mason-restore "$WORK_DIR/rebuild/editor_tools.json" "$WORK_DIR/nvim" "$SCRIPT_DIR/nvim_plugins.lua" --json >"$WORK_DIR/mason-preflight.json"
  set_result mason_tools unverified 'Pinned tool records and destination paths passed read-only preflight; reconstruction/functional checks pending.'
fi
if [ -d "$WORK_DIR/research_workflow" ]; then
  CURRENT_COMPONENT=research_workflow
  python3 -B "$HELPER" authority-state "$WORK_DIR/research_workflow" "$TARGET_HOME/Research_Workflow" >"$WORK_DIR/authority-state.json" || {
    cat "$WORK_DIR/authority-state.json" >&2
    status ERROR 'Portable authority differs; use the separately authorized Research_Workflow merge/validate workflow.'
    exit 1
  }
  authority_state=$(python3 -B -c 'import json,sys;print(json.load(open(sys.argv[1]))["state"])' "$WORK_DIR/authority-state.json")
fi
CURRENT_COMPONENT=preflight
CONFIG_CHOICES="$WORK_DIR/config-choices.json"
python3 -B - "$CONFIG_CHOICES" "$WORK_DIR/set.json" <<'PY_CHOICES'
from pathlib import Path
import hashlib,json,sys
path=Path(sys.argv[2])
saved=(json.dumps(json.loads(path.read_text()),sort_keys=True,indent=2)+'\n').encode() if path.is_file() else None
value={'set_sha256':hashlib.sha256(saved).hexdigest() if saved is not None else 'legacy','choices':{}}
Path(sys.argv[1]).write_text(json.dumps(value)+'\n')
PY_CHOICES
choose_stow_content() {
  local relative=$1 package_path=$2 effective repository current_target current_source choice info
  effective="$WORK_DIR/credentials/$relative"
  repository="$WORK_DIR/dot_files/$package_path"
  [ -f "$effective" ] && [ -f "$repository" ] || return 0
  CURRENT_COMPONENT=credentials
  python3 -B "$HELPER" content-info "$effective" >"$WORK_DIR/effective-info.json"
  python3 -B "$HELPER" content-info "$repository" >"$WORK_DIR/repository-info.json"
  current_target="$TARGET_HOME/$relative"
  current_source="$TARGET_HOME/dot_files/$package_path"
  choice=$(python3 -B - "$HELPER" "$WORK_DIR/effective-info.json" "$WORK_DIR/repository-info.json" "$CONFIG_CHOICES" "$TARGET_HOME/.local/share/arch-recovery/$RECOVERY_ID/config-choices.json" "$relative" "$current_target" "$current_source" <<'PY_CHOICE'
from pathlib import Path
import importlib.util,json,sys
spec=importlib.util.spec_from_file_location('b2',sys.argv[1]);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
effective=json.load(open(sys.argv[2]));repository=json.load(open(sys.argv[3]));current=json.load(open(sys.argv[4]))
if effective['sha256']==repository['sha256']:
 print('effective')
else:
 choice='ask'
 try:
  receipt_path=Path(sys.argv[5]);module.regular_parents(receipt_path.parent)
  if receipt_path.is_symlink():raise ValueError('Linked receipt')
  saved=json.loads(receipt_path.read_text());row=saved['choices'][sys.argv[6]]
  if row['choice'] not in ('effective','repository'):raise ValueError('Invalid saved choice')
  target=Path(sys.argv[7]);source=Path(sys.argv[8])
  expected=effective if row['choice']=='effective' else repository
  if saved['set_sha256']==current['set_sha256'] and row['effective']==effective and row['repository']==repository and target.is_symlink() and target.resolve()==source.resolve() and module.content_info(source)==expected:
   choice=row['choice']
 except (OSError,RuntimeError,ValueError,KeyError,TypeError):pass
 print(choice)
PY_CHOICE
)
  if [ "$choice" = ask ]; then
    printf 'Archived effective file: %s\n' "$current_target"
    cat "$WORK_DIR/effective-info.json"
    printf 'Archived Stow source: %s\n' "$current_source"
    cat "$WORK_DIR/repository-info.json"
    printf 'Both archived versions remain in the selected encrypted set.\n'
    printf 'Choose effective to update the exact Stow source above, or repository to use its archived content.\n'
    read -r -p 'Type effective or repository: ' choice </dev/tty
    [[ "$choice" = effective || "$choice" = repository ]] || { status ERROR 'No configuration content selected.'; exit 1; }
  else
    status SKIP "Content choice already equivalent or previously verified: $relative ($choice)."
  fi
  python3 -B - "$CONFIG_CHOICES" "$relative" "$choice" "$WORK_DIR/effective-info.json" "$WORK_DIR/repository-info.json" <<'PY_SAVE_CHOICE'
import json,sys
from pathlib import Path
path=Path(sys.argv[1]);value=json.loads(path.read_text())
value['choices'][sys.argv[2]]={'choice':sys.argv[3],'effective':json.load(open(sys.argv[4])),'repository':json.load(open(sys.argv[5]))}
path.write_text(json.dumps(value,sort_keys=True)+'\n')
PY_SAVE_CHOICE
  if [ "$choice" = effective ]; then
    cp --preserve=mode,timestamps -- "$effective" "$repository"
  fi
  CREDENTIAL_EXCLUDES+=(--exclude-path "$relative")
}
if [ -d "$WORK_DIR/credentials" ] && [ -d "$WORK_DIR/dot_files" ]; then
  choose_stow_content .gitconfig git/.gitconfig
  choose_stow_content .config/rclone/rclone.conf rclone/.config/rclone/rclone.conf
fi
CURRENT_COMPONENT=preflight
for pair in system:/ home:"$TARGET_HOME" credentials:"$TARGET_HOME" scripts:"$TARGET_HOME/scripts" dot_files:"$TARGET_HOME/dot_files" research_workflow:"$TARGET_HOME/Research_Workflow"; do
  name=${pair%%:*}; target=${pair#*:}
  if [ -d "$WORK_DIR/$name" ]; then
    python3 -B "$HELPER" diff "$WORK_DIR/$name" "$target" >"$WORK_DIR/$name.diff.json"
  fi
done
set_result preflight verified 'All selected payloads passed structural preflight; encrypted content was staged privately; existing authority checked.'
confirm 'All available payloads passed preflight. Start privileged recovery, including package transactions and user setup?'
RESTORE_BACKUP_DIR=$(mktemp -d /root/arch_restore_backup_XXXXXXXX)
field 'Safety backup' "$RESTORE_BACKUP_DIR"

preserve_path() {
  local target=$1 backup
  python3 -B "$HELPER" parents "$(dirname "$target")"
  if [ -e "$target" ] || [ -L "$target" ]; then
    backup="$RESTORE_BACKUP_DIR/${target#/}"
    if [ -e "$backup" ] || [ -L "$backup" ]; then backup="$backup.$RANDOM.$RANDOM"; fi
    python3 -B "$HELPER" parents "$(dirname "$backup")"
    mkdir -p "$(dirname "$backup")"
    mv -T -- "$target" "$backup"
    LAST_BACKUP="$backup"
    status OK "Preserved $target at $backup"
  fi
}
deploy_tree() {
  local source=$1 target=$2 owner=$3 action rel type path detail
  shift 3
  local extra=("$@")
  local plan="$WORK_DIR/deploy.$RANDOM"
  python3 -B "$HELPER" diff "$source" "$target" --nul "${extra[@]}" >"$plan"
  if [ ! -d "$target" ]; then mkdir -p "$target"; chown "$owner" "$target"; fi
  while IFS= read -r -d '' action && IFS= read -r -d '' rel && IFS= read -r -d '' type && IFS= read -r -d '' detail; do
    path="$target/$rel"
    printf 'Difference: %s\n' "$detail"
    confirm "$action $type: $path"
    if [ "$action" = metadata ]; then
      local metadata_backup
      metadata_backup=$(mktemp "$RESTORE_BACKUP_DIR/directory-metadata.XXXXXXXX")
      python3 -B - "$path" "$metadata_backup" <<'PY_META'
import json,os,stat,sys
from pathlib import Path
path=Path(sys.argv[1]);info=path.lstat()
if not stat.S_ISDIR(info.st_mode):raise SystemExit('Directory changed before metadata preservation.')
Path(sys.argv[2]).write_text(json.dumps({'path':str(path),'mode':stat.S_IMODE(info.st_mode),'uid':info.st_uid,'gid':info.st_gid})+'\n')
PY_META
      chmod --reference="$source/$rel" "$path"
      chown "$owner" "$path"
      status OK "Preserved directory metadata at $metadata_backup"
      continue
    fi
    preserve_path "$path"
    mkdir -p "$(dirname "$path")"
    if [ "$type" = directory ]; then
      mkdir -- "$path"; chmod --reference="$source/$rel" "$path"
    else cp -a --no-clobber -- "$source/$rel" "$path"; fi
    chown -h "$owner" "$path"
  done <"$plan"
  python3 -B "$HELPER" diff "$source" "$target" "${extra[@]}" >"$WORK_DIR/deployed.json"
  python3 -B - "$WORK_DIR/deployed.json" <<'PY'
import json,sys
if any(row['action']!='same' for row in json.load(open(sys.argv[1]))):raise SystemExit('Deployment differs; safety backups retained.')
PY
}

CURRENT_COMPONENT=system
step 2/8 'Restore selected system configuration and prepare target user.'
[ ! -d "$WORK_DIR/system" ] || deploy_tree "$WORK_DIR/system" / root:root
if ! id "$TARGET_USER" >/dev/null 2>&1; then
  confirm "Create $TARGET_USER with wheel membership and NOPASSWD: ALL?"
  useradd -m -G wheel -s /bin/bash "$TARGET_USER"
  confirm 'Install /etc/sudoers.d/wheel_nopasswd with NOPASSWD: ALL, preserving any existing file?'
  preserve_path /etc/sudoers.d/wheel_nopasswd
  printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/wheel_nopasswd
  chmod 440 /etc/sudoers.d/wheel_nopasswd
fi

mkdir -p "$WORK_DIR/system_defaults/etc"
REGENERATE_LOCALE=false
if [ -f /etc/locale.gen ] && grep -q '^#en_US.UTF-8 UTF-8' /etc/locale.gen; then
  [ ! -L /etc/locale.gen ] || { status ERROR 'Linked /etc/locale.gen requires separate review.'; exit 1; }
  sed 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen >"$WORK_DIR/system_defaults/etc/locale.gen"
  chmod --reference=/etc/locale.gen "$WORK_DIR/system_defaults/etc/locale.gen"
  REGENERATE_LOCALE=true
  if [ ! -e /etc/locale.conf ]; then
    printf 'LANG=en_US.UTF-8\n' >"$WORK_DIR/system_defaults/etc/locale.conf"
    chmod 644 "$WORK_DIR/system_defaults/etc/locale.conf"
  fi
fi
if [ ! -e /etc/wsl.conf ]; then
  printf '[user]\ndefault=%s\n' "$TARGET_USER" >"$WORK_DIR/system_defaults/etc/wsl.conf"
  chmod 644 "$WORK_DIR/system_defaults/etc/wsl.conf"
elif ! grep -q '^\[user\]' /etc/wsl.conf; then
  [ -f /etc/wsl.conf ] && [ ! -L /etc/wsl.conf ] || { status ERROR 'Linked /etc/wsl.conf requires separate review.'; exit 1; }
  cp -p -- /etc/wsl.conf "$WORK_DIR/system_defaults/etc/wsl.conf"
  printf '\n[user]\ndefault=%s\n' "$TARGET_USER" >>"$WORK_DIR/system_defaults/etc/wsl.conf"
fi
deploy_tree "$WORK_DIR/system_defaults" / root:root --synthetic-directory etc
if [ "$REGENERATE_LOCALE" = true ]; then
  confirm 'Generate the enabled system locales with locale-gen?'
  locale-gen
fi

set_result system verified 'Selected system files, applicable locale/user settings and directory metadata checked.'

pacman_with_official_mirror() {
  if ! grep -Eq '^[[:space:]]*Include[[:space:]]*=[[:space:]]*/etc/pacman\.d/mirrorlist[[:space:]]*$' /etc/pacman.conf; then
    status ERROR "Cannot construct the official-mirror Pacman configuration."
    return 1
  fi

  pacman --config <(
    awk -v server="$PACMAN_FALLBACK_MIRROR" '
      /^[[:space:]]*Include[[:space:]]*=[[:space:]]*\/etc\/pacman\.d\/mirrorlist[[:space:]]*$/ {
        print server
        next
      }
      { print }
    ' /etc/pacman.conf
  ) "$@"
}

update_keyring_with_retry() {
  if pacman -Sy --needed --noconfirm archlinux-keyring; then
    return
  fi

  status WARN "Keyring update failed; retrying once through the official Arch geo mirror."
  pacman_with_official_mirror -Syy --needed --noconfirm archlinux-keyring
}

pacman_upgrade_and_install() {
  if pacman -Syu --needed --noconfirm "$@"; then
    return
  fi

  status WARN "Package transaction failed; retrying once through the official Arch geo mirror."
  pacman_with_official_mirror -Syyu --needed --noconfirm "$@"
}

CURRENT_COMPONENT=packages
step 3/8 'Install recorded official and AUR packages.'
field 'Topiary dependency packages' "${TOPIARY_PACKAGES[*]:-none}"
field 'Formatter/linter packages' "${FORMATTER_PACKAGES[*]:-none recorded}"
confirm "Upgrade Arch and install ${#PACMAN_PACKAGES[@]} official packages, the displayed editor/Topiary dependency packages and ${#AUR_PACKAGES[@]} AUR packages? Package versions follow current repositories."
if [ ! -d /etc/pacman.d/gnupg ]; then pacman-key --init; pacman-key --populate archlinux; fi
update_keyring_with_retry
pacman_upgrade_and_install base-devel git stow sudo tar openssh gnupg python bubblewrap "${CORE_ARCH_PACKAGES[@]}" "${PACMAN_PACKAGES[@]}" "${TOPIARY_PACKAGES[@]}" "${FORMATTER_PACKAGES[@]}"
if [ "${#AUR_PACKAGES[@]}" -gt 0 ]; then
  if ! command -v yay >/dev/null; then
    confirm "Fetch https://aur.archlinux.org/yay-bin.git into a new temporary directory, then build/install as $TARGET_USER using git and base-devel? This uses current AUR source, not a frozen package artifact."
    IFS=$'\t' read -r YAY_BUILD_DIR YAY_BUILD_ID < <(python3 -B "$HELPER" temp-create arch-restore-yay.)
    chown "$TARGET_USER:$TARGET_USER" "$YAY_BUILD_DIR"
    if sudo -H -u "$TARGET_USER" env http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$SOCKS_URL" git clone -- https://aur.archlinux.org/yay-bin.git "$YAY_BUILD_DIR/source" &&
      sudo -H -u "$TARGET_USER" env http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$SOCKS_URL" bash -c 'cd "$1" && makepkg -si --noconfirm' bash "$YAY_BUILD_DIR/source"; then
      CODEX_TEMP_CLEANUP=1 python3 -B "$HELPER" cleanup "$YAY_BUILD_DIR" "$YAY_BUILD_ID"
    else
      status ERROR "AUR bootstrap failed. Build evidence retained: $YAY_BUILD_DIR"
      exit 1
    fi
  fi
  sudo -H -u "$TARGET_USER" env http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$SOCKS_URL" yay -S --needed --noconfirm -- "${AUR_PACKAGES[@]}"
fi

pacman -Q "${CORE_ARCH_PACKAGES[@]}" >"$WORK_DIR/core-installed.txt"
set_result packages verified 'Package transactions completed; four selected Arch editor dependencies are installed. Runtime behavior is reported separately.'
set_result jukit_core unverified 'Core Arch packages installed; provider/cell/output/conversion checks are still pending.'

import_authority() {
  local stage_root identity name source target
  confirm "Import the complete metadata and policy snapshot into the empty authority at $TARGET_HOME/Research_Workflow? Keep Research_Workflow writers stopped until acceptance."
  stage_root=$(mktemp -d "$TARGET_HOME/Research_Workflow/.authority-import.XXXXXXXX")
  identity=$(python3 -B "$HELPER" temp-id "$stage_root")
  CLEANUP_PATHS+=("$stage_root"); CLEANUP_IDS+=("$identity")
  for name in metadata policy; do
    cp -a -- "$WORK_DIR/research_workflow/$name" "$stage_root/$name"
    chown -R "$TARGET_USER:$TARGET_USER" "$stage_root/$name"
  done
  for name in metadata policy; do
    source="$stage_root/$name"; target="$TARGET_HOME/Research_Workflow/$name"
    printf 'Authority import: %s\n' "$target"
    python3 -B - "$source" "$target" <<'PY_AUTHORITY_IMPORT'
import os,sys
from pathlib import Path
source=Path(sys.argv[1]);target=Path(sys.argv[2])
# Rename may replace an empty directory, never a populated authority tree.
if target.is_symlink():raise SystemExit('Authority target became a link; refusing import.')
os.rename(source,target)
PY_AUTHORITY_IMPORT
  done
  python3 -B "$HELPER" authority-state "$WORK_DIR/research_workflow" "$TARGET_HOME/Research_Workflow" >"$WORK_DIR/authority-imported.json"
}

step 4/8 'Restore selected worktrees, home configuration and credentials.'
for pair in scripts:scripts dot_files:dot_files research_workflow:Research_Workflow; do
  name=${pair%:*}; subdir=${pair#*:}
  if [ -d "$WORK_DIR/$name" ]; then
    CURRENT_COMPONENT="$name"
    if [ "$name" = research_workflow ]; then
      python3 -B "$HELPER" authority-state "$WORK_DIR/$name" "$TARGET_HOME/$subdir" >"$WORK_DIR/authority-recheck.json" || { cat "$WORK_DIR/authority-recheck.json" >&2; exit 1; }
      authority_state=$(python3 -B -c 'import json,sys;print(json.load(open(sys.argv[1]))["state"])' "$WORK_DIR/authority-recheck.json")
      deploy_tree "$WORK_DIR/$name" "$TARGET_HOME/$subdir" "$TARGET_USER:$TARGET_USER" --exclude-path metadata --exclude-path policy
      if [ "$authority_state" = empty ]; then import_authority
      else status SKIP 'Matching metadata and policy retained without writes.'; fi
      set_result "$name" verified "Code deployed; portable authority $authority_state handled without journal replacement; compatibility checked, full device acceptance remains separate."
    else
      deploy_tree "$WORK_DIR/$name" "$TARGET_HOME/$subdir" "$TARGET_USER:$TARGET_USER"
      if [ "$name" = dot_files ]; then set_result dot_files unverified 'Selected worktree contents deployed; Stow and effective-content checks pending.'
      else set_result "$name" verified 'Selected members and metadata match; unrelated content retained.'; fi
    fi
  fi
done
if [ -d "$WORK_DIR/home" ]; then
  CURRENT_COMPONENT=home
  deploy_tree "$WORK_DIR/home" "$TARGET_HOME" "$TARGET_USER:$TARGET_USER"
  set_result home verified 'Selected home file contents and metadata match.'
fi
if [ -d "$WORK_DIR/credentials" ]; then
  CURRENT_COMPONENT=credentials
  deploy_tree "$WORK_DIR/credentials" "$TARGET_HOME" "$TARGET_USER:$TARGET_USER" "${CREDENTIAL_EXCLUDES[@]}"
  set_result credentials unverified 'Selected direct credentials match; chosen Stow-managed effective files await final checks.'
fi

CURRENT_COMPONENT=dot_files
step 5/8 'Preflight and deploy the restored Stow packages.'
deploy_stow() {
  local path name rel source target index result
  local packages=() planned_targets=()
  STOW_MOVED_TARGETS=(); STOW_MOVED_BACKUPS=()
  for path in "$WORK_DIR/dot_files"/*/; do
    [ -d "$path" ] || continue
    name=$(basename "$path")
    [[ "$name" != [-+]* ]] || { status ERROR 'Unsafe Stow package name.'; return 1; }
    packages+=("$name")
  done
  [ "${#packages[@]}" -gt 0 ] || { status ERROR 'No archived Stow packages found.'; return 1; }
  printf 'Stow packages: %s\n' "${packages[*]}"
  for rel in git/.gitconfig ssh/.ssh/config rclone/.config/rclone/rclone.conf; do
    source="$TARGET_HOME/dot_files/$rel"; target="$TARGET_HOME/${rel#*/}"
    [ -e "$source" ] || continue
    if [ -L "$target" ] && [ "$(realpath "$target")" = "$(realpath "$source")" ]; then continue; fi
    if [ -e "$target" ] || [ -L "$target" ]; then
      printf 'Chosen Stow source: %s\n' "$source"
      python3 -B "$HELPER" content-info "$source"
      confirm "Preserve $target and link to the chosen content above?"
      planned_targets+=("$target")
    fi
  done
  rollback_stow() {
    local index target failed=0
    for index in "${!STOW_MOVED_BACKUPS[@]}"; do
      target=${STOW_MOVED_TARGETS[index]}
      if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        if ! mv -T -- "${STOW_MOVED_BACKUPS[index]}" "$target"; then
          status ERROR "Could not restore $target; original retained at ${STOW_MOVED_BACKUPS[index]}"
          failed=1
        fi
      else status WARN "Current path retained: $target; original: ${STOW_MOVED_BACKUPS[index]}"; fi
    done
    return "$failed"
  }
  STOW_ROLLBACK_PENDING=true
  for target in "${planned_targets[@]}"; do
    if ! preserve_path "$target"; then rollback_stow; STOW_ROLLBACK_PENDING=false; return 1; fi
    STOW_MOVED_TARGETS+=("$target"); STOW_MOVED_BACKUPS+=("$LAST_BACKUP")
  done
  result=0
  sudo -H -u "$TARGET_USER" stow --dir "$TARGET_HOME/dot_files" --simulate --verbose=1 --no-folding --stow --target "$TARGET_HOME" "${packages[@]}" >"$WORK_DIR/stow-plan.txt" 2>&1 || result=$?
  if [ "$result" -eq 0 ]; then
    if grep -Eq '^(LINK|UNLINK|MKDIR|RMDIR): ' "$WORK_DIR/stow-plan.txt"; then
      cat "$WORK_DIR/stow-plan.txt"
      confirm 'Apply these exact Stow link/directory changes?'
      sudo -H -u "$TARGET_USER" stow --dir "$TARGET_HOME/dot_files" --no-folding --stow --target "$TARGET_HOME" "${packages[@]}" || result=$?
    else
      status SKIP 'Stow reports no link or directory changes; existing links retained.'
    fi
  fi
  if [ "$result" -ne 0 ]; then
    cat "$WORK_DIR/stow-plan.txt" >&2
    rollback_stow
    STOW_ROLLBACK_PENDING=false
    status ERROR 'Stow failed; rollback was attempted for absent originals, and retained paths/backups are reported above.'
    return "$result"
  fi
  STOW_ROLLBACK_PENDING=false
}
if [ -d "$WORK_DIR/dot_files" ]; then deploy_stow
else status SKIP 'No dot_files snapshot; no remote repository operation or Stow deployment.'; fi
if [ -d "$WORK_DIR/dot_files" ]; then
  python3 -B - "$HELPER" "$CONFIG_CHOICES" "$TARGET_HOME" <<'PY_VERIFY_CHOICE'
from pathlib import Path
import importlib.util,json,sys
spec=importlib.util.spec_from_file_location('b2',sys.argv[1]);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
choices=json.load(open(sys.argv[2]))['choices'];home=Path(sys.argv[3])
for relative,choice in choices.items():
 expected=choice[choice['choice']];target=home/relative
 if not target.is_symlink():raise SystemExit('Selected effective configuration is not a Stow link.')
 if module.content_info(target.resolve())!=expected:raise SystemExit('Effective Stow content differs from the selected archive version.')
PY_VERIFY_CHOICE
  set_result dot_files verified 'Selected worktree and Stow links match the confirmed effective/source choices.'
fi
if [ -d "$WORK_DIR/credentials" ]; then set_result credentials verified 'File contents, modes and selected Stow targets match; SSH login and GPG key use are untested.'; fi


step 6/8 'Restore selected tool dependencies, then validate the offline editor.'
topiary_probe() {
  local binary=$1 mode=$2
  local command=(/tmp/topiary --version) cache=()
  if [ "$mode" = dependencies ]; then command=(/usr/bin/ldd /tmp/topiary); fi
  if [ -f /etc/ld.so.cache ]; then cache=(--ro-bind /etc/ld.so.cache /etc/ld.so.cache); fi
  timeout --signal=TERM --kill-after=5s 30s bwrap --die-with-parent --new-session \
    --unshare-net --unshare-pid --unshare-ipc --unshare-uts --cap-drop ALL \
    --ro-bind /usr /usr --symlink usr/bin /bin --symlink usr/lib /lib --symlink usr/lib /lib64 \
    --dev /dev --proc /proc --dir /etc "${cache[@]}" --tmpfs /tmp --dir /tmp/home \
    --ro-bind "$binary" /tmp/topiary --clearenv --setenv PATH /usr/bin:/bin \
    --setenv HOME /tmp/home --setenv LC_ALL C --chdir /tmp/home -- "${command[@]}"
}
if [ -d "$WORK_DIR/topiary" ]; then
  CURRENT_COMPONENT=topiary
  topiary_probe "$WORK_DIR/topiary/bin/topiary" dependencies >"$WORK_DIR/topiary-target-dependencies.txt"
  python3 -IB - "$WORK_DIR/topiary/runtime.json" "$WORK_DIR/topiary-target-dependencies.txt" "$WORK_DIR/topiary-target-runtime.json" "$SCRIPT_DIR" <<'PY_TOPIARY_CHECK'
from pathlib import Path
import hashlib,json,os,subprocess,sys
sys.path.insert(0,sys.argv[4])
from topiary_dependencies import resolved_dependencies,match_recorded
record=Path(sys.argv[1]);saved=json.loads(record.read_text());report=[]
try:
 actual=resolved_dependencies(record.parent/'bin/topiary',Path(sys.argv[2]).read_text(encoding='utf-8'))
 pairs=match_recorded(saved['dependencies'],actual)
except (ValueError,OSError,RuntimeError) as error:raise SystemExit(str(error)) from None
for row,found in pairs:
 path=Path(found['realpath']);source=row['source']
 with path.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
 info={**found,'sha256':digest,'same_bytes':digest==row['sha256']}
 if source['manager']=='pacman':
  owner=subprocess.run(['/usr/bin/pacman','-Qoq',str(path.resolve())],capture_output=True,text=True,check=True,env={**os.environ,'LC_ALL':'C'}).stdout.strip()
  if owner!=source['package']:raise SystemExit('Topiary dependency package source differs; review required.')
  version=subprocess.run(['/usr/bin/pacman','-Q',owner],capture_output=True,text=True,check=True).stdout.strip().split(maxsplit=1)
  if len(version)!=2 or version[0]!=owner:raise SystemExit('Topiary dependency version is unavailable.')
  info.update(package=owner,saved_version=source['version'],installed_version=version[1])
 elif digest!=row['sha256']:raise SystemExit('Unmanaged Topiary dependency bytes differ; compatibility is unknown.')
 report.append(info)
Path(sys.argv[3]).write_text(json.dumps({'dependencies':report,'validation':'target loader resolution; version check and grammar acceptance are separate'},indent=2)+'\n')
print(json.dumps(report,indent=2))
PY_TOPIARY_CHECK
  mkdir -p "$WORK_DIR/topiary-deploy/usr/local/bin"
  cp -p -- "$WORK_DIR/topiary/bin/topiary" "$WORK_DIR/topiary-deploy/usr/local/bin/topiary"
  deploy_tree "$WORK_DIR/topiary-deploy" / root:root --synthetic-directory usr --synthetic-directory usr/local --synthetic-directory usr/local/bin
  topiary_probe /usr/local/bin/topiary version >"$WORK_DIR/topiary-version.txt"
  cmp -- "$WORK_DIR/topiary/version.txt" "$WORK_DIR/topiary-version.txt"
  grammar_relative=".cache/topiary/nu/$TOPIARY_NU_REVISION/grammar.so"
  mkdir -p "$WORK_DIR/topiary-grammar/$(dirname "$grammar_relative")"
  cp -p -- "$WORK_DIR/topiary/grammar/nu.so" "$WORK_DIR/topiary-grammar/$grammar_relative"
  deploy_tree "$WORK_DIR/topiary-grammar" "$TARGET_HOME" "$TARGET_USER:$TARGET_USER" \
    --synthetic-directory .cache --synthetic-directory .cache/topiary --synthetic-directory .cache/topiary/nu \
    --synthetic-directory ".cache/topiary/nu/$TOPIARY_NU_REVISION"
  mkdir -p "$WORK_DIR/rebuild"
  cp -- "$WORK_DIR/topiary/runtime.json" "$WORK_DIR/rebuild/topiary-source.json"
  cp -- "$WORK_DIR/topiary-target-runtime.json" "$WORK_DIR/rebuild/topiary-target.json"
  set_result topiary unverified 'Original Topiary binary/version and accepted fixed-revision Nu grammar bytes/mode restored at original paths; no library write or grammar download. Target formatter behavior requires separate functional acceptance.'
fi
if [ "$NVIM_READY" = true ] || [ "$RAYFILE_READY" = true ]; then
  make_temp USER_STAGE arch-restore-user.
  cp -- "$SCRIPT_DIR/nvim_state.py" "$SCRIPT_DIR/nvim_plugins.lua" "$SCRIPT_DIR/rayfile_state.py" "$SCRIPT_DIR/mason_tools.py" "$SCRIPT_DIR/backup_set.py" "$USER_STAGE/"
  [ "$NVIM_READY" = false ] || cp -a -- "$WORK_DIR/nvim" "$USER_STAGE/"
  [ "$RAYFILE_READY" = false ] || cp -a -- "$WORK_DIR/rayfile" "$USER_STAGE/"
  if [ -f "$WORK_DIR/rebuild/editor_tools.json" ]; then cp -- "$WORK_DIR/rebuild/editor_tools.json" "$USER_STAGE/editor_tools.json"; fi
  chown -R "$TARGET_USER:$TARGET_USER" "$USER_STAGE"
fi
if [ "$NVIM_READY" = true ]; then
  CURRENT_COMPONENT=mason_tools
  if [ ! -f "$USER_STAGE/editor_tools.json" ]; then
    status ERROR 'Editor tool reconstruction metadata is missing; exact Mason recovery cannot proceed.'
    exit 1
  fi
  sudo -H -u "$TARGET_USER" python3 -B "$USER_STAGE/nvim_state.py" --home "$TARGET_HOME" \
    mason-restore "$USER_STAGE/editor_tools.json" "$USER_STAGE/nvim" "$USER_STAGE/nvim_plugins.lua" --json >"$WORK_DIR/mason-preview.json"
  mason_identity=$(python3 -B -c 'import json,sys;v=json.load(open(sys.argv[1]));assert v["status"]=="preview";print(v["identity"])' "$WORK_DIR/mason-preview.json")
  cat "$WORK_DIR/mason-preview.json"
  printf 'Mason plan identity: %s\n' "$mason_identity"
  confirm 'Run the displayed pinned Mason reconstruction/validation at the original tool paths? Only the displayed missing or changed tools may use network/build/install operations.'
  sudo -H -u "$TARGET_USER" python3 -B "$USER_STAGE/nvim_state.py" --home "$TARGET_HOME" \
    mason-restore "$USER_STAGE/editor_tools.json" "$USER_STAGE/nvim" "$USER_STAGE/nvim_plugins.lua" --expect-identity "$mason_identity" --run --json >"$WORK_DIR/mason-result.json"
  python3 -B - "$WORK_DIR/mason-result.json" <<'PY_MASON_RESULT'
import json,sys
value=json.load(open(sys.argv[1]))
if value.get('status')!='verified' or value.get('validated') is not True:raise SystemExit('Mason recovery is not validated.')
tools=value.get('tools',{})
if len(tools)!=4 or any(row.get('validated') is not True or row.get('status') not in ('verified','skipped') for row in tools.values()):raise SystemExit('Incomplete Mason tool validation.')
for name,row in tools.items():print(f"[TOOL] {name}: {row['status']} - {row.get('reason','')}")
PY_MASON_RESULT
  set_result mason_tools verified 'All four selected original-path Mason tools passed pinned-source/content and real executable checks; unchanged tools were skipped.'

  CURRENT_COMPONENT=nvim
  sudo -H -u "$TARGET_USER" python3 -B "$USER_STAGE/nvim_state.py" --home "$TARGET_HOME" equivalent "$USER_STAGE/nvim" --json >"$WORK_DIR/nvim-equivalent.json"
  equivalent=$(python3 -B -c 'import json,sys;print("true" if json.load(open(sys.argv[1]))["equivalent"] else "false")' "$WORK_DIR/nvim-equivalent.json")
  if [ "$equivalent" = true ]; then
    generation=$(python3 -B -c 'import json,sys;print(json.load(open(sys.argv[1]))["generation"])' "$WORK_DIR/nvim-equivalent.json")
    sudo -H -u "$TARGET_USER" python3 -B "$USER_STAGE/nvim_state.py" --home "$TARGET_HOME" validate "$generation" --json >"$WORK_DIR/nvim-result.json"
    status SKIP 'The active generation has identical payload content; no generation or activation change.'
  else
    sudo -H -u "$TARGET_USER" python3 -B "$USER_STAGE/nvim_state.py" --home "$TARGET_HOME" \
      restore "$USER_STAGE/nvim" "$USER_STAGE/nvim_plugins.lua" --run --json >"$WORK_DIR/nvim-result.json"
    generation=$(python3 -B -c 'import json,sys; v=json.load(open(sys.argv[1])); assert v["status"]=="validated"; print(v["generation"])' "$WORK_DIR/nvim-result.json")
  fi
  CURRENT_COMPONENT=jukit_core
  python3 -B - "$WORK_DIR/nvim-result.json" <<'PY_CORE_RESULT'
import json,sys
value=json.load(open(sys.argv[1]));core=value.get('jukit_core_validation',{})
if value.get('status')!='validated' or core.get('passed') is not True or core.get('level')!='real-isolated-integration':raise SystemExit('Editor core validation is incomplete.')
for name in ('provider','cell_edit','cell_run','output_save','core_conversion'):
 if core.get(name)!='passed':raise SystemExit('Missing real editor core check: '+name)
PY_CORE_RESULT
  set_result jukit_core verified 'Real system provider, cell editing/run, saved output and core .py/.ipynb conversion passed; browser/HTML/PDF extras are excluded.'
  if [ -d "$WORK_DIR/topiary" ] && python3 -B - "$WORK_DIR/nvim-result.json" <<'PY_TOPIARY_RESULT'
import json,sys
value=json.load(open(sys.argv[1])).get('formatter_validation',{})
raise SystemExit(0 if value.get('passed') is True and value.get('topiary_nu')=='conform-offline-format' else 1)
PY_TOPIARY_RESULT
  then
    set_result topiary verified 'Original binary and fixed-revision Nu grammar bytes/mode restored; target version and real offline Conform Nu formatting passed. System libraries were not overwritten.'
  fi
  CURRENT_COMPONENT=nvim
  if [ "$equivalent" != true ]; then
    identity=$(python3 -B -c 'import json,sys;print(json.load(open(sys.argv[1]))["identity"])' "$WORK_DIR/nvim-result.json")
    printf 'Activation: sudo -H -u %q python3 -B %q --home %q activate %q --expect-identity %q --run --json\n' "$TARGET_USER" "$USER_STAGE/nvim_state.py" "$TARGET_HOME" "$generation" "$identity"
    confirm "Activate validated Neovim generation $generation with identity $identity? Previous generations remain available."
    sudo -H -u "$TARGET_USER" python3 -B "$USER_STAGE/nvim_state.py" --home "$TARGET_HOME" activate "$generation" --expect-identity "$identity" --run --json
  fi
  set_result nvim verified 'Active config/runtime/plugins/parsers match the selected payload and passed current dependency validation.'
else
  set_result jukit_core uncovered 'Core system packages installed, but no offline-ready Neovim snapshot is available for end-to-end acceptance.'
  set_result mason_tools uncovered 'No validated staged editor/Mason runtime is available for exact tool reconstruction.'
fi
if [ "$RAYFILE_READY" = true ]; then
  CURRENT_COMPONENT=rayfile
  sudo -H -u "$TARGET_USER" python3 -B "$USER_STAGE/backup_set.py" rayfile-equivalent "$USER_STAGE/rayfile" "$TARGET_HOME" "$USER_STAGE/rayfile_state.py" >"$WORK_DIR/rayfile-equivalent.json"
  if python3 -B -c 'import json,sys;raise SystemExit(0 if json.load(open(sys.argv[1]))["equivalent"] else 1)' "$WORK_DIR/rayfile-equivalent.json"; then
    sudo -H -u "$TARGET_USER" python3 -B "$USER_STAGE/rayfile_state.py" verify --home "$TARGET_HOME"
    status SKIP 'Rayfile managed runtime bytes, permissions and launcher already match; no replacement or safety copy.'
  else
    confirm 'Restore the saved Rayfile runtime and launcher, preserving the current installation?'
    sudo -H -u "$TARGET_USER" python3 -B "$USER_STAGE/rayfile_state.py" restore "$USER_STAGE/rayfile" --home "$TARGET_HOME"
  fi
  set_result rayfile verified 'Managed runtime and launcher content/permissions checked; --version succeeded; transfers/resume remain unverified.'
fi

CURRENT_COMPONENT=formatter_linter_tools
if [ -f "$WORK_DIR/rebuild/editor_tools.json" ] && python3 -B -c 'import json,sys;raise SystemExit(0 if "formatter_linter_tools" in json.load(open(sys.argv[1])) else 1)' "$WORK_DIR/rebuild/editor_tools.json"; then
  if [ -z "$USER_STAGE" ]; then
    make_temp USER_STAGE arch-restore-user.
    chown "$TARGET_USER:$TARGET_USER" "$USER_STAGE"
  fi
  cp -- "$SCRIPT_DIR/nvim_state.py" "$SCRIPT_DIR/mason_tools.py" "$USER_STAGE/"
  cp -- "$WORK_DIR/rebuild/editor_tools.json" "$USER_STAGE/formatter-tools.json"
  chown "$TARGET_USER:$TARGET_USER" "$USER_STAGE/nvim_state.py" "$USER_STAGE/mason_tools.py" "$USER_STAGE/formatter-tools.json"
  sudo -H -u "$TARGET_USER" env PATH=/usr/local/bin:/usr/bin:/bin python3 -B "$USER_STAGE/nvim_state.py" --home "$TARGET_HOME" \
    formatter-check "$USER_STAGE/formatter-tools.json" --json >"$WORK_DIR/rebuild/formatter-linter-check.json"
  formatter_state=$(python3 -B - "$WORK_DIR/rebuild/formatter-linter-check.json" <<'PY_FORMATTER_RESULT'
import json,sys
value=json.load(open(sys.argv[1]));tools=value.get('tools',{})
if set(tools)!={'isort','black','shfmt','markdownlint','clang-tidy','pylint'} or value.get('status') not in ('verified','unverified'):raise SystemExit('Invalid formatter/linter verification result.')
for name,row in tools.items():
 if row.get('status') not in ('verified','unverified','uncovered') or row.get('validation')!='source-and-version-only':raise SystemExit('Invalid per-tool verification result.')
 print(f"[TOOL] {name}: {row['status']} - {row.get('reason','')}",file=sys.stderr)
if value['status']=='verified' and any(row['status']!='verified' for row in tools.values()):raise SystemExit('Inconsistent formatter/linter result.')
print(value['status'])
PY_FORMATTER_RESULT
)
  set_result formatter_linter_tools "$formatter_state" 'Six recorded tools checked for executable bytes/path, package source and version; this is not formatter/linter integration acceptance. Per-tool drift/uncovered reasons retained in formatter-linter-check.json.'
else
  set_result formatter_linter_tools uncovered 'No six-tool source/reconstruction records in this backup; no inferred dependency success.'
fi

step 7/8 'Restore the default shell.'
if [ -f "$WORK_DIR/packages/default_shell.txt" ]; then
  CURRENT_COMPONENT=packages
  shell_path=$(cat "$WORK_DIR/packages/default_shell.txt")
  if [[ "$shell_path" == /* && "$shell_path" != *$'\n'* ]] && [ -f "$shell_path" ] && [ -x "$shell_path" ]; then
    if ! grep -Fxq "$shell_path" /etc/shells; then
      [ -f /etc/shells ] && [ ! -L /etc/shells ] || { status ERROR 'Unsupported /etc/shells target.'; exit 1; }
      mkdir -p "$WORK_DIR/shell_config/etc"
      cp -p -- /etc/shells "$WORK_DIR/shell_config/etc/shells"
      printf '%s\n' "$shell_path" >>"$WORK_DIR/shell_config/etc/shells"
      deploy_tree "$WORK_DIR/shell_config" / root:root --synthetic-directory etc
    fi
    if [ "$(getent passwd "$TARGET_USER" | cut -d: -f7)" = "$shell_path" ]; then
      status SKIP 'Default shell already matches.'
    else
      confirm "Set $TARGET_USER's default shell to $shell_path?"
      chsh -s "$shell_path" "$TARGET_USER"
    fi
    set_result packages verified 'Package transactions, four Arch editor dependencies and selected default shell checked.'
  else
    status ERROR 'Recorded shell is unavailable or invalid; current shell and safety backups retained.'
    exit 1
  fi
elif [ -n "$SET_DIR" ]; then
  status ERROR 'The selected set lacks its default-shell record.'
  exit 1
fi
if [ -d "$WORK_DIR/rebuild" ]; then
  CURRENT_COMPONENT=rebuild
  cp -- "$CONFIG_CHOICES" "$WORK_DIR/rebuild/config-choices.json"
  deploy_tree "$WORK_DIR/rebuild" "$TARGET_HOME/.local/share/arch-recovery/$RECOVERY_ID" "$TARGET_USER:$TARGET_USER"
  set_result rebuild verified 'Version/source/path records and configuration choices saved; this status does not certify unexecuted reconstructions.'
  if python3 -B -c 'import json,sys;raise SystemExit(0 if not json.load(open(sys.argv[1])).get("npm") else 1)' "$WORK_DIR/rebuild/npm.json"; then
    set_result private_npm skipped 'No private npm packages were recorded.'
  else
    set_result private_npm uncovered 'Private npm versions/sources recorded; whole Node trees and automatic private-package installation are outside the selected recovery.'
  fi
fi
step 8/8 'Retain safety backups and report each component.'
CURRENT_COMPONENT=""
if [ -n "$LEGACY_DIR" ]; then
  RESTORE_OUTCOME=legacy
  status WARN 'Legacy recovery ended with unproven batch consistency; see per-component omissions.'
  exit 3
fi
RESTORE_OUTCOME=finished
printf 'Selected recovery operations finished. Per-component evidence and limits follow.\n'
status SKIP 'No user-repository synchronization, upload or old-backup cleanup.'
