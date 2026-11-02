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
SRC_DIR="$SCRIPT_DIR/src"
HELPER="$SRC_DIR/backup_set.py"
PREVIEW=false
WORKFLOW_ARGS=()
TOOL_PROXY_ENV=()
SET_DIR=""
LEGACY_DIR=""
CORE_ARCH_PACKAGES=(python-pynvim ipython python-matplotlib python-pylatexenc)
TOPIARY_NU_REVISION=18b7f951e0c511f854685dfcc9f6a34981101dd6
TOPIARY_NU_SHA256=6507a874e74108a380a043daefffc71ed3ead75beb46101df21f0792800cdad1

COLOR=false
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then COLOR=true; fi
status() {
  local label=$1 message=$2 color=36
  case "$label" in OK) color=32 ;; WARN|SKIP) color=33 ;; ERROR) color=31 ;; esac
  if [ "$label" = ERROR ]; then
    if [ "$COLOR" = true ] && [ -t 2 ]; then printf '\033[%sm[%s]\033[0m %s\n' "$color" "$label" "$message" >&2
    else printf '[%s] %s\n' "$label" "$message" >&2; fi
  elif [ "$COLOR" = true ]; then printf '\033[%sm[%s]\033[0m %s\n' "$color" "$label" "$message"
  else printf '[%s] %s\n' "$label" "$message"; fi
}
subtask() { printf '  [%s] %s\n' "${2:-RUN}" "$1" >&2; }
field() { printf '%s: %s\n' "$1" "$2"; }
usage() {
  printf '%s\n' "Usage: $0 [--set PATH | --legacy PATH] [--keep-local-workflow] [--use-tool-proxy] [--preview]" "" \
    "Restore an explicitly selected Arch backup; real mode is the default." \
    "Without a path, use data/github-current. Managed replacements run without confirmation." "" \
    "Options:" "  --set PATH    Published data/github-current or a complete ID-named set." \
    "  --legacy PATH Old archlinux directory containing data/ and pkg_lists/." \
    "  --keep-local-workflow  Keep the complete existing Research_Workflow checkout." \
    "  --use-tool-proxy  Route tool HTTP(S) downloads through $PROXY_URL." \
    "  --preview     Compare public backup records and local workflow authority without decryption." \
    "  -h, --help    Show this help." "" \
    "Examples:" "  bash backup/archlinux/restore.sh --preview" \
    "  sudo bash backup/archlinux/restore.sh --set /path/to/data/github-current"
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --preview) PREVIEW=true; shift ;;
    --keep-local-workflow) WORKFLOW_ARGS=(--keep-local-workflow); shift ;;
    --use-tool-proxy) TOOL_PROXY_ENV=(http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" no_proxy="localhost,127.0.0.1,::1"); shift ;;
    --set|--legacy)
      [ "$#" -ge 2 ] && [[ "$2" != --* ]] || { status ERROR "$1 requires a path."; exit 2; }
      [ -z "$SET_DIR$LEGACY_DIR" ] || { status ERROR 'Choose exactly one backup source.'; exit 2; }
      if [ "$1" = --set ]; then SET_DIR=$(realpath -m "$2"); else LEGACY_DIR=$(realpath -m "$2"); fi
      shift 2 ;;
    *) status ERROR "Unknown argument: $1."; usage >&2; exit 2 ;;
  esac
done
if [ "$COLOR" = true ]; then printf '\n\033[36mArch Linux WSL restore\033[0m\n'
else printf '\nArch Linux WSL restore\n'; fi
field Target "$TARGET_HOME, selected /etc files and /usr/local/bin/topiary"
field Mode "$([ "$PREVIEW" = true ] && printf preview || printf run)"
field Rule 'check sources first; replace managed paths; roll back and clean on failure'
field Privileges 'new target user: wheel membership and NOPASSWD: ALL'
field 'Editor core' "${CORE_ARCH_PACKAGES[*]}; system provider/IPython before Neovim validation"
field 'Base packages' 'base-devel git stow sudo tar openssh gnupg python bubblewrap'
field Packages 'Pacman system upgrade/install and AUR install; observed old versions are a rebuild record, not a downgrade promise'
field Repositories 'verify published commits over HTTPS for scripts/dot_files and SSH for Research_Workflow'
field Proxy "AUR HTTP=$PROXY_URL SOCKS=$SOCKS_URL; package fallback=https://geo.mirror.pkgbuild.com"
if [ "${#TOOL_PROXY_ENV[@]}" -gt 0 ]; then field 'Tool downloads' "HTTP(S) proxy $PROXY_URL"; fi
field 'AUR bootstrap' 'if yay is missing: https://aur.archlinux.org/yay-bin.git, new private build directory, target-user makepkg; included in this restore command'
if [ -z "$SET_DIR$LEGACY_DIR" ]; then SET_DIR="$CURRENT_SET"; fi
field Source "${SET_DIR:-$LEGACY_DIR}"
if [ -n "$LEGACY_DIR" ] && [ "${#WORKFLOW_ARGS[@]}" -gt 0 ]; then
  status ERROR '--keep-local-workflow applies to complete sets; legacy recovery has no workflow payload.'
  exit 2
fi
if [ -n "$SET_DIR" ] && { [ ! -d "$SET_DIR" ] || [ ! -f "$SET_DIR/manifest.json" ] || [ -L "$SET_DIR/manifest.json" ]; }; then
  status ERROR "Missing set directory or regular manifest at: $SET_DIR (working directory: $PWD)"
  status ERROR "Use the published set: --set $CURRENT_SET"
  exit 2
fi
if [ "${#WORKFLOW_ARGS[@]}" -gt 0 ]; then field Research_Workflow "preserve complete local checkout at $TARGET_HOME/Research_Workflow"; fi
public_preflight() {
  python3 -B "$HELPER" restore-preflight "$SET_DIR" "$TARGET_HOME/Research_Workflow" "${WORKFLOW_ARGS[@]}" "$@" || {
    status ERROR 'Public preflight stopped. For divergent authority, reconcile separately or explicitly select --keep-local-workflow for an existing checkout.'
    return 1
  }
}
if [ "$PREVIEW" = true ]; then
  if [ -n "$SET_DIR" ]; then
    public_preflight
    status DRY-RUN 'Public hashes and archive structure verified; workflow action shown above; other destination differences require private staging.'
  else status WARN 'Legacy payloads cannot prove same-batch consistency; no complete-set success will be reported.'; fi
  status DRY-RUN 'No credential access, decryption, package operations or target writes.'
  exit 0
fi
[ "$EUID" -eq 0 ] || { status ERROR 'Run real recovery as root.'; exit 1; }
[ -t 0 ] || { status ERROR 'Recovery requires a terminal for the encrypted-backup passphrase.'; exit 1; }

umask 077
unset GPG_PASS
WORK_DIR=""
GPG_ROOT=""
GPG_ROOT_ID=""
GPG_HOME_ID=""
GPG_HOME=""
USER_STAGE=""
GITHUB_SSH_ID=""
PACMAN_CACHE=""
YAY_BUILD_DIR=""
YAY_BUILD_ID=""
RESTORE_BACKUP_DIR=""
SET_FORMAT=1
ROLLBACK_FAILED=false
CURRENT_COMPONENT="preflight"
RESTORE_OUTCOME="running"
CREDENTIAL_EXCLUDES=()
CLEANUP_PATHS=()
CLEANUP_IDS=()
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
  case "$variable" in WORK_DIR|USER_STAGE|PACMAN_CACHE) ;; *) return 1 ;; esac
  IFS=$'\t' read -r path identity < <(python3 -B "$HELPER" temp-create "$prefix")
  CLEANUP_PATHS+=("$path"); CLEANUP_IDS+=("$identity")
  printf -v "$variable" '%s' "$path"
}
ensure_crypto_home() {
  if [ -z "$GPG_ROOT" ]; then
    IFS=$'\t' read -r GPG_ROOT GPG_ROOT_ID < <(python3 -IB "$SRC_DIR/backup_crypto.py" start) || return 1
    GPG_HOME="$GPG_ROOT/gpg-home"
    GPG_HOME_ID=$(python3 -B "$HELPER" temp-id "$GPG_HOME") || return 1
  fi
  python3 -B "$HELPER" check-temp "$GPG_ROOT" "$GPG_ROOT_ID" || return 1
  python3 -B "$HELPER" check-temp "$GPG_HOME" "$GPG_HOME_ID"
}
stop_crypto_agent() {
  if [ -n "$GPG_ROOT" ]; then
    local path="$GPG_ROOT"
    GPG_ROOT=""
    if ! CODEX_TEMP_CLEANUP=1 python3 -IB "$SRC_DIR/backup_crypto.py" close "$path" "$GPG_ROOT_ID"; then
      status ERROR "Private crypto directory retained for review: $path"
      return 1
    fi
  fi
}
clear_github_ssh() {
  [ -n "$GITHUB_SSH_ID" ] || return 0
  CODEX_TEMP_CLEANUP=1 python3 -B "$HELPER" cleanup "$USER_STAGE/github-ssh" "$GITHUB_SSH_ID" || {
    status ERROR "Could not safely remove temporary GitHub identity: $USER_STAGE/github-ssh"
    return 1
  }
  GITHUB_SSH_ID=""
}
cleanup_restore_tmp() {
  local index failed=0
  unset GPG_PASS
  clear_github_ssh || failed=1
  stop_crypto_agent || failed=1
  for ((index=${#CLEANUP_PATHS[@]}-1; index>=0; index--)); do
    if [ -n "$GITHUB_SSH_ID" ] && [ "${CLEANUP_PATHS[index]}" = "$USER_STAGE" ]; then continue; fi
    if [ "$ROLLBACK_FAILED" = true ] && { [ "${CLEANUP_PATHS[index]}" = "$WORK_DIR" ] || [ "${CLEANUP_PATHS[index]}" = "$USER_STAGE" ]; }; then
      status ERROR "Rollback originals retained at ${CLEANUP_PATHS[index]}"
      failed=1
      continue
    fi
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
  trap '' INT TERM HUP
  if [ "$code" -ne 0 ] && [ "$RESTORE_OUTCOME" != legacy ]; then
    [ -z "$CURRENT_COMPONENT" ] || set_result "$CURRENT_COMPONENT" failed "Stopped with exit $code."
    for journal in "${USER_STAGE:-/nonexistent}/transaction" "${WORK_DIR:-/nonexistent}/transaction"; do
      if [ -f "$journal/journal.json" ]; then
        if ! python3 -B "$HELPER" transaction "$journal" rollback; then ROLLBACK_FAILED=true; fi
      fi
    done
  fi
  subtask 'Clean invocation staging'
  if cleanup_restore_tmp; then
    set_result cleanup verified 'Owned temporary paths removed; no private GPG runtime remains for this invocation.'
  else
    set_result cleanup failed 'Cleanup was stopped safely; see the exact retained temporary paths above.'
    [ "$code" -ne 0 ] || code=1
  fi
  report_restore
  exit "$code"
}
trap finish_restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
for command in python3 tar gpg gpgconf pacman git; do
  command -v "$command" >/dev/null || { status ERROR "Preflight dependency missing: $command."; exit 1; }
done
make_temp WORK_DIR arch-restore-payload.
NVIM_READY=false
RECIPE=""
PINNED_TOOLS=()
RAYFILE_READY=false

status 1/8 'Verify every archive, encrypted internal manifest, architecture and staging space.'
if [ -n "$SET_DIR" ]; then
  subtask 'Verify the complete backup and component hashes'
  public_preflight --manifest-output "$WORK_DIR/set.json"
  SET_FORMAT=$(python3 -B -c 'import json,sys;print(json.load(open(sys.argv[1]))["format"])' "$WORK_DIR/set.json")
  python3 -B - "$WORK_DIR/set.json" "$WORK_DIR/components" "$WORK_DIR/component-states" "${WORKFLOW_ARGS[@]}" <<'PY'
import json,sys
from pathlib import Path
value=json.loads(Path(sys.argv[1]).read_text())
with Path(sys.argv[2]).open('w') as out:
 for name,row in value['components'].items():
  if row['state']=='present' and name!='scripts' and not (name=='research_workflow' and sys.argv[4:]):
   out.write(name+'\t'+row['file']+'\n')
with Path(sys.argv[3]).open('w') as out:
 for name,row in value['components'].items():
  if value['format']==2 and name in ('dot_files','research_workflow','nvim','topiary','rayfile'):
   out.write(name+'\tunverified\tAwaiting pinned source records.\n')
   continue
  reason='Payload selected; not yet staged.' if row['state']=='present' else row['reason']
  reason=''.join(c if ord(c)>=32 else ' ' for c in reason)
  out.write(name+'\t'+('unverified' if row['state']=='present' else 'skipped')+'\t'+reason+'\n')
PY
  while IFS=$'\t' read -r name state reason; do set_result "$name" "$state" "$reason"; done <"$WORK_DIR/component-states"
  if [ "${#WORKFLOW_ARGS[@]}" -gt 0 ]; then
    set_result research_workflow skipped 'Preserved the complete local Research_Workflow checkout by explicit request.'
  fi
  while IFS=$'\t' read -r name filename; do
    cp -- "$SET_DIR/$filename" "$WORK_DIR/$filename"
  done <"$WORK_DIR/components"
  python3 -B - "$WORK_DIR/set.json" "$WORK_DIR" "${WORKFLOW_ARGS[@]}" <<'PY_COPY'
import hashlib,json,sys
from pathlib import Path
value=json.loads(Path(sys.argv[1]).read_text());root=Path(sys.argv[2])
for name,row in value['components'].items():
 if row['state']=='present' and name!='scripts' and not (name=='research_workflow' and sys.argv[3:]):
  with (root/row['file']).open('rb') as stream:
   if hashlib.file_digest(stream,'sha256').hexdigest()!=row['sha256']:raise SystemExit('Copied payload changed.')
PY_COPY
  while IFS=$'\t' read -r name filename; do
    CURRENT_COMPONENT="$name"
    subtask "Verify and stage $name"
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
        python3 -B "$SRC_DIR/nvim_state.py" --home "$TARGET_HOME" stage "$archive" "$WORK_DIR/nvim" --json >"$WORK_DIR/nvim-stage.json"
        python3 -B -c 'import json,sys; v=json.load(open(sys.argv[1])); assert v["status"]=="ready" and v["format"]==2' "$WORK_DIR/nvim-stage.json"
        NVIM_READY=true ;;
      rayfile)
        mkdir "$WORK_DIR/rayfile"
        python3 -B "$SRC_DIR/rayfile_state.py" stage "$archive" "$WORK_DIR/rayfile"
        RAYFILE_READY=true ;;
      *) python3 -B "$HELPER" stage "$archive" "$WORK_DIR/$name" --require-catalog >/dev/null ;;
    esac
    set_result "$name" unverified 'Archive structure, architecture and available hashes checked; deployment pending.'
  done <"$WORK_DIR/components"
  unset GPG_PASS
  if [ -d "$WORK_DIR/research_workflow" ] && [ "${#WORKFLOW_ARGS[@]}" -eq 0 ]; then
    python3 -B "$WORK_DIR/research_workflow/tools/researchctl.py" --workspace "$WORK_DIR/no-device.toml" \
      doctor --compatibility-only --store "$WORK_DIR/research_workflow/metadata/STORE.json" --json
  fi
else
  status WARN 'Legacy recovery cannot establish batch consistency; optional missing components remain missing.'
  for component in packages system home credentials scripts dot_files research_workflow topiary nvim rayfile rebuild; do
    set_result "$component" skipped 'Not present in the selected legacy layout.'
  done
  subtask 'Check legacy configuration and package lists'
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
    python3 -B "$SRC_DIR/nvim_state.py" --home "$TARGET_HOME" stage "$LEGACY_DIR/data/nvim.tar.gz" "$WORK_DIR/nvim" --json >"$WORK_DIR/nvim-stage.json" 2>"$WORK_DIR/nvim-stage.err" || stage_exit=$?
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
    python3 -B "$SRC_DIR/rayfile_state.py" stage "$LEGACY_DIR/data/rayfile.tar.gz" "$WORK_DIR/rayfile"
    RAYFILE_READY=true
  fi
fi

if [ "$SET_FORMAT" = 2 ]; then
  CURRENT_COMPONENT=rebuild
  RECIPE="$WORK_DIR/rebuild/downloads.json"
  [ -f "$RECIPE" ] || { status ERROR 'Missing pinned download records.'; exit 1; }
  selected=$(python3 -B - "$RECIPE" <<'PY_SELECTED'
import json, sys
with open(sys.argv[1], encoding='utf-8') as stream:
    recipe = json.load(stream)
if not isinstance(recipe, dict) or recipe.get('format') != 1:
    raise SystemExit('[ERROR] Unsupported download recipe.')
selected = []
for name in ('nvim', 'topiary', 'rayfile'):
    if name != 'nvim' and name in recipe and recipe[name] is None:
        continue
    if not isinstance(recipe.get(name), dict) or not recipe[name]:
        raise SystemExit('[ERROR] Invalid pinned source record: ' + name)
    selected.append(name)
print(' '.join(selected))
PY_SELECTED
)
  read -r -a PINNED_TOOLS <<<"$selected"
  for name in topiary rayfile; do set_result "$name" skipped 'No source recorded on the backup device.'; done
  for name in "${PINNED_TOOLS[@]}"; do set_result "$name" pending 'Selected for reconstruction after the package stage.'; done
fi

# Check project publication before any destination change.
CURRENT_COMPONENT=preflight
make_temp USER_STAGE arch-restore-user.
cp -- "$SRC_DIR"/{backup_set.py,rebuild_tools.py,nvim_state.py,nvim_plugins.lua,mason_tools.py,rayfile_state.py} "$USER_STAGE/"
SOURCE_RUNNER=()
WORKFLOW_SSH=()
if [ "$SET_FORMAT" = 2 ]; then cp -- "$RECIPE" "$USER_STAGE/downloads.json"; fi
if id "$TARGET_USER" >/dev/null 2>&1; then
  SOURCE_RUNNER=(sudo -H -u "$TARGET_USER")
  if [ -e "$TARGET_HOME/Research_Workflow" ] || { [ "$SET_FORMAT" = 2 ] && [ "${#WORKFLOW_ARGS[@]}" -eq 0 ]; }; then
    CURRENT_COMPONENT=research_workflow
    subtask 'Check GitHub SSH access for Research_Workflow'
    workflow_url=git@github.com:YuhanJin-USTC/Research_Workflow.git
    probe=(sudo -H -u "$TARGET_USER" env LC_ALL=C GIT_TERMINAL_PROMPT=0)
    strict_ssh='ssh -o BatchMode=yes -o StrictHostKeyChecking=yes'
    ssh_command=$strict_ssh
    configured=$("${probe[@]}" git -C / config --get core.sshCommand) || { [ "$?" -eq 1 ] || exit 1; }
    case "$configured" in
      ''|ssh|/usr/bin/ssh|/usr/sbin/ssh) ;;
      'ssh '*|'/usr/bin/ssh '*|'/usr/sbin/ssh '*) ssh_command+=" ${configured#* }" ;;
      *) status ERROR 'Research_Workflow preflight requires an OpenSSH command with strict host checking.'; exit 1 ;;
    esac
    effective=$("${probe[@]}" git -C / ls-remote --get-url -- "$workflow_url")
    [ "$effective" = "$workflow_url" ] || { status ERROR 'Git URL rewrite changes the Research_Workflow SSH address.'; exit 1; }
    if message=$("${probe[@]}" GIT_SSH_COMMAND="$ssh_command" timeout 30 git -C / ls-remote --exit-code -- "$workflow_url" HEAD 2>&1); then
      WORKFLOW_SSH=("GIT_SSH_COMMAND=$ssh_command")
    else
      case "$message" in
        *'REMOTE HOST IDENTIFICATION HAS CHANGED'*|*'Offending '*|*'REVOKED HOST KEY'*) status ERROR "$message"; exit 1 ;;
        *'Permission denied (publickey'*|*'Too many authentication failures'*|*'ERROR: Repository not found.'*|*'host key is known for '*|*"Can't open user config file"*"No such file or directory"*)
          subtask 'Use the saved GitHub identity for Research_Workflow'
          saved="$WORK_DIR/credentials/.ssh"
          private="$USER_STAGE/github-ssh"
          python3 -B "$HELPER" parents "$saved"
          for file in id_github known_hosts; do
            [ -s "$saved/$file" ] && [ -f "$saved/$file" ] && [ ! -L "$saved/$file" ] || {
              status ERROR "Missing or unsafe saved SSH file: $file. Configure GitHub SSH for $TARGET_USER."
              exit 1
            }
          done
          # Populate before the target user owns the staging parent.
          mkdir -m 700 -- "$private"
          GITHUB_SSH_ID=$(python3 -B "$HELPER" temp-id "$private")
          install -m 600 -- "$saved/id_github" "$saved/known_hosts" "$private/"
          WORKFLOW_SSH=("GIT_SSH_COMMAND=$strict_ssh -F /dev/null -o IdentityAgent=none -o IdentitiesOnly=yes -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$private/known_hosts -i $private/id_github")
          ;;
        *) status ERROR "Research_Workflow SSH check failed: ${message:-no response}"; exit 1 ;;
      esac
    fi
  fi
  chown -R "$TARGET_USER:$TARGET_USER" "$USER_STAGE"
else
  # A new account uses the key pairs directly from private payload staging.
  saved="$WORK_DIR/credentials/.ssh"
  ssh_args=(ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$saved/known_hosts")
  for public in "$saved/"*.pub; do
    key=${public%.pub}
    if [ -f "$public" ] && [ -f "$key" ] && [ ! -L "$key" ]; then ssh_args+=(-i "$key"); fi
  done
  printf -v ssh_command '%q ' "${ssh_args[@]}"
  WORKFLOW_SSH=("GIT_SSH_COMMAND=$ssh_command")
fi
source_project() {
  local command=$1 project=$2
  shift 2
  local auth=()
  if [ "$project" = research_workflow ]; then auth=("${WORKFLOW_SSH[@]}"); fi
  "${SOURCE_RUNNER[@]}" env "${auth[@]}" python3 -B "$USER_STAGE/rebuild_tools.py" "$command" \
    --home "$TARGET_HOME" --work "$USER_STAGE/source-check" --project "$project" "$@"
}
for name in scripts dot_files research_workflow; do
  CURRENT_COMPONENT="$name"
  subtask "Check published source for $name"
  source_project check-targets "$name"
done
CURRENT_COMPONENT=preflight
if [ "$SET_FORMAT" = 2 ]; then
  for name in dot_files research_workflow; do
    if [ "$name" = research_workflow ] && [ "${#WORKFLOW_ARGS[@]}" -gt 0 ]; then continue; fi
    CURRENT_COMPONENT="$name"
    set_result "$name" unverified 'Preparing the pinned project in private staging.'
    source_project projects "$name" --recipe "$USER_STAGE/downloads.json" --target "$USER_STAGE"
    cp -a -- "$USER_STAGE/$name" "$WORK_DIR/$name"
    set_result "$name" unverified 'Pinned project staged; deployment pending.'
  done
fi
clear_github_ssh
if [ "$SET_FORMAT" = 2 ] && [ -d "$WORK_DIR/research_workflow" ]; then
  CURRENT_COMPONENT=research_workflow
  python3 -B "$WORK_DIR/research_workflow/tools/researchctl.py" --workspace "$WORK_DIR/no-device.toml" doctor --compatibility-only --store "$WORK_DIR/research_workflow/metadata/STORE.json" --json
fi
CURRENT_COMPONENT=preflight
set_result scripts skipped 'The executing scripts checkout is retained; no self-snapshot deployment.'

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
  status WARN 'yay is missing; restore will bootstrap it in private staging.'
fi

# Reject targets or payloads outside the selected component scope.
python3 -B - "$WORK_DIR" "$TARGET_HOME" "$TOPIARY_NU_REVISION" "$TOPIARY_NU_SHA256" "$SET_FORMAT" <<'PY'
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
for name in (() if sys.argv[5]=='2' else ('scripts','dot_files','research_workflow')):
 base=root/name
 for path in base.rglob('*') if base.exists() else []:
  if '.git' in path.parts:raise SystemExit('Git metadata unexpectedly included.')
 for blocked in ('.git', '.codex', '.agents'):
  if (base/blocked).exists() or (base/blocked).is_symlink():raise SystemExit('Unexpected worktree state in archive.')
for rel in (() if sys.argv[5]=='2' else ('scripts/backup/archlinux/data','scripts/backup/archlinux/pkg_lists','research_workflow/workspace.toml','research_workflow/.research-workflow')):
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
  python3 -B "$SRC_DIR/nvim_state.py" --home "$TARGET_HOME" \
    mason-restore "$WORK_DIR/rebuild/editor_tools.json" "$WORK_DIR/nvim" "$SRC_DIR/nvim_plugins.lua" --json >"$WORK_DIR/mason-preflight.json"
  set_result mason_tools unverified 'Pinned tool records and destination paths passed read-only preflight; reconstruction/functional checks pending.'
fi
if [ "$SET_FORMAT" = 1 ] && [ "${#WORKFLOW_ARGS[@]}" -eq 0 ] && [ -d "$WORK_DIR/research_workflow" ]; then
  CURRENT_COMPONENT=research_workflow
  python3 -B "$HELPER" authority-state "$WORK_DIR/research_workflow" "$TARGET_HOME/Research_Workflow" >"$WORK_DIR/authority-state.json" || {
    cat "$WORK_DIR/authority-state.json" >&2
    status ERROR 'Portable authority differs; use the separately authorized Research_Workflow merge/validate workflow.'
    exit 1
  }
  authority_state=$(python3 -B -c 'import json,sys;print(json.load(open(sys.argv[1]))["state"])' "$WORK_DIR/authority-state.json")
fi
CURRENT_COMPONENT=preflight
# Git-managed credential files use the published repository content.
if [ -d "$WORK_DIR/dot_files" ]; then
  for pair in .gitconfig:git/.gitconfig .config/rclone/rclone.conf:rclone/.config/rclone/rclone.conf; do
    relative=${pair%%:*}; package_path=${pair#*:}
    if [ -f "$WORK_DIR/credentials/$relative" ] && [ -f "$WORK_DIR/dot_files/$package_path" ]; then
      if ! cmp -s -- "$WORK_DIR/credentials/$relative" "$WORK_DIR/dot_files/$package_path"; then
        status ERROR "Saved effective configuration differs from its published source: $relative. Reconcile it before restoring."
        exit 1
      fi
      CREDENTIAL_EXCLUDES+=(--exclude-path "$relative")
    fi
  done
fi
if [ "${#WORKFLOW_ARGS[@]}" -gt 0 ]; then
  for path in "$WORK_DIR/home/Research_Workflow" "$WORK_DIR/credentials/Research_Workflow" \
      "$WORK_DIR"/dot_files/*/Research_Workflow; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      status ERROR 'A different component targets the locally preserved Research_Workflow directory.'
      exit 1
    fi
  done
  for package in "$WORK_DIR"/dot_files/*/; do
    [ -d "$package" ] || continue
    path="$TARGET_HOME/dot_files/$(basename "$package")/Research_Workflow"
    if [ -e "$path" ] || [ -L "$path" ]; then status ERROR "Existing Stow package targets the preserved checkout: $path"; exit 1; fi
  done
fi
CURRENT_COMPONENT=preflight
for pair in system:/ home:"$TARGET_HOME" credentials:"$TARGET_HOME"; do
  name=${pair%%:*}; target=${pair#*:}
  if [ "$name" = research_workflow ] && [ "${#WORKFLOW_ARGS[@]}" -gt 0 ]; then continue; fi
  if [ -d "$WORK_DIR/$name" ]; then
    python3 -B "$HELPER" diff "$WORK_DIR/$name" "$target" >"$WORK_DIR/$name.diff.json"
  fi
done
set_result preflight verified 'All selected payloads passed structural preflight; encrypted content was staged privately; existing authority checked.'
RESTORE_BACKUP_DIR="$WORK_DIR/transaction"
transaction() { python3 -B "$HELPER" transaction "$RESTORE_BACKUP_DIR" "$@"; }
preserve_path() {
  local target=$1
  python3 -B "$HELPER" parents "$(dirname "$target")"
  transaction save "$target"
  if [ -e "$target" ] || [ -L "$target" ]; then
    mv -T -- "$target" "$WORK_DIR/replaced.$RANDOM.$RANDOM"
  fi
}

deploy_tree() {
  local source=$1 target=$2 owner=$3 action rel type path detail
  shift 3
  local extra=("$@")
  local plan="$WORK_DIR/deploy.$RANDOM"
  python3 -B "$HELPER" diff "$source" "$target" --nul "${extra[@]}" >"$plan"
  if [ ! -d "$target" ]; then transaction parents "$target"; chown "$owner" "$target"; fi
  while IFS= read -r -d '' action && IFS= read -r -d '' rel && IFS= read -r -d '' type && IFS= read -r -d '' detail; do
    path="$target/$rel"
    if [ "$action" = metadata ]; then
      transaction metadata "$path"
      chmod --reference="$source/$rel" "$path"
      chown "$owner" "$path"
      continue
    fi
    preserve_path "$path"
    transaction parents "$(dirname "$path")"
    if [ "$type" = directory ]; then
      mkdir -- "$path"; chmod --reference="$source/$rel" "$path"
    else cp -a --no-clobber -- "$source/$rel" "$path"; fi
    chown -h "$owner" "$path"
  done <"$plan"
  python3 -B "$HELPER" diff "$source" "$target" "${extra[@]}" >"$WORK_DIR/deployed.json"
  python3 -B - "$WORK_DIR/deployed.json" <<'PY'
import json,sys
if any(row['action']!='same' for row in json.load(open(sys.argv[1]))):raise SystemExit('Deployment differs; invocation rollback will restore the original files.')
PY
}

CURRENT_COMPONENT=system
status 2/8 'Restore selected system configuration and prepare target user.'
subtask 'Prepare system configuration and target account'
[ ! -d "$WORK_DIR/system" ] || deploy_tree "$WORK_DIR/system" / root:root
if ! id "$TARGET_USER" >/dev/null 2>&1; then
  useradd -m -G wheel -s /bin/bash "$TARGET_USER"
  chown -R "$TARGET_USER:$TARGET_USER" "$USER_STAGE"
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
  locale-gen
fi

set_result system verified 'Selected system files, applicable locale/user settings and directory metadata checked.'

pacman_with_official_mirror() {
  if ! grep -Eq '^[[:space:]]*Include[[:space:]]*=[[:space:]]*/etc/pacman\.d/mirrorlist[[:space:]]*$' /etc/pacman.conf; then
    status ERROR "Cannot construct the official-mirror Pacman configuration."
    return 1
  fi

  pacman --cachedir "$PACMAN_CACHE" --config <(
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
  if pacman --cachedir "$PACMAN_CACHE" -Sy --needed --noconfirm archlinux-keyring; then
    return
  fi

  status WARN "Keyring update failed; retrying once through the official Arch geo mirror."
  pacman_with_official_mirror -Syy --needed --noconfirm archlinux-keyring
}

pacman_upgrade_and_install() {
  if pacman --cachedir "$PACMAN_CACHE" -Syu --needed --noconfirm "$@"; then
    return
  fi

  status WARN "Package transaction failed; retrying once through the official Arch geo mirror."
  pacman_with_official_mirror -Syyu --needed --noconfirm "$@"
}

CURRENT_COMPONENT=packages
status 3/8 'Install recorded official and AUR packages.'
make_temp PACMAN_CACHE arch-restore-pacman.
# Pacman's DownloadUser must traverse the cache to reach its download-* directory.
chmod 0755 -- "$PACMAN_CACHE"
field 'Topiary dependency packages' "${TOPIARY_PACKAGES[*]:-none}"
field 'Formatter/linter packages' "${FORMATTER_PACKAGES[*]:-none recorded}"
package_steps=1
if [ "${#AUR_PACKAGES[@]}" -gt 0 ]; then package_steps=2; fi
subtask 'Install official packages' "1/$package_steps"
if [ ! -d /etc/pacman.d/gnupg ]; then pacman-key --init; pacman-key --populate archlinux; fi
update_keyring_with_retry
pacman_upgrade_and_install base-devel git stow sudo tar openssh gnupg python bubblewrap rust cmake pkgconf "${CORE_ARCH_PACKAGES[@]}" "${PACMAN_PACKAGES[@]}" "${TOPIARY_PACKAGES[@]}" "${FORMATTER_PACKAGES[@]}"
if [ "${#AUR_PACKAGES[@]}" -gt 0 ]; then
  subtask 'Install AUR packages' "2/$package_steps"
  if ! command -v yay >/dev/null; then
    IFS=$'\t' read -r YAY_BUILD_DIR YAY_BUILD_ID < <(python3 -B "$HELPER" temp-create arch-restore-yay.)
    CLEANUP_PATHS+=("$YAY_BUILD_DIR"); CLEANUP_IDS+=("$YAY_BUILD_ID")
    chown "$TARGET_USER:$TARGET_USER" "$YAY_BUILD_DIR"
    if sudo -H -u "$TARGET_USER" env http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$SOCKS_URL" git clone -- https://aur.archlinux.org/yay-bin.git "$YAY_BUILD_DIR/source" &&
      sudo -H -u "$TARGET_USER" env http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$SOCKS_URL" bash -c 'cd "$1" && makepkg -si --noconfirm' bash "$YAY_BUILD_DIR/source"; then
      CODEX_TEMP_CLEANUP=1 python3 -B "$HELPER" cleanup "$YAY_BUILD_DIR" "$YAY_BUILD_ID"
    else
      status ERROR "AUR bootstrap failed; invocation cleanup will remove its build directory."
      exit 1
    fi
  fi
  sudo -H -u "$TARGET_USER" env http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$SOCKS_URL" XDG_CACHE_HOME="$USER_STAGE/cache" yay -S --builddir "$USER_STAGE/aur" --cachedir "$PACMAN_CACHE" --needed --noconfirm -- "${AUR_PACKAGES[@]}"
else
  subtask 'No AUR packages recorded' SKIP
fi

pacman -Q "${CORE_ARCH_PACKAGES[@]}" >"$WORK_DIR/core-installed.txt"
set_result packages verified 'Package transactions completed; four selected Arch editor dependencies are installed. Runtime behavior is reported separately.'
set_result jukit_core unverified 'Core Arch packages installed; provider/cell/output/conversion checks are still pending.'

status 4/8 'Rebuild pinned tools and restore home configuration.'
if [ "$SET_FORMAT" = 2 ]; then
  chown -R "$TARGET_USER:$TARGET_USER" "$USER_STAGE"
  run_rebuild() {
    sudo -H -u "$TARGET_USER" env ARCH_RESTORE_PROGRESS=1 "${TOOL_PROXY_ENV[@]}" TMPDIR="$USER_STAGE/tmp" python3 -B "$USER_STAGE/rebuild_tools.py" "$@" --home "$TARGET_HOME" --recipe "$USER_STAGE/downloads.json" --work "$USER_STAGE/build"
  }
  mkdir -p "$USER_STAGE/tmp"
  chown "$TARGET_USER:$TARGET_USER" "$USER_STAGE/tmp"
  for name in "${PINNED_TOOLS[@]}"; do
    CURRENT_COMPONENT="$name"
    subtask "Rebuild pinned tool  $name"
    case "$name" in
      nvim) run_rebuild editor --config "$USER_STAGE/dot_files/nvim/.config/nvim" --target "$USER_STAGE/nvim"; NVIM_READY=true ;;
      topiary) run_rebuild topiary --config "$USER_STAGE/dot_files/topiary/.config/topiary" --target "$USER_STAGE/topiary" ;;
      rayfile) run_rebuild rayfile --target "$USER_STAGE/rayfile" ;;
    esac
    set_result "$name" unverified 'Pinned tool staged; installation and verification pending.'
  done
fi
for pair in dot_files:dot_files research_workflow:Research_Workflow; do
  name=${pair%:*}; subdir=${pair#*:}
  [ -d "$WORK_DIR/$name" ] || continue
  CURRENT_COMPONENT="$name"
  subtask "Deploy project  $subdir"
  if [ "$SET_FORMAT" = 2 ]; then
    if [ -d "$TARGET_HOME/$subdir/.git" ]; then
      revision=$(python3 -B -c 'import json,sys;print(json.load(open(sys.argv[1]))["projects"][sys.argv[2]]["commit"])' "$RECIPE" "$name")
      project_git=(sudo -H -u "$TARGET_USER" git --no-optional-locks -C "$TARGET_HOME/$subdir" -c core.hooksPath=/dev/null -c core.fsmonitor=false)
      sudo -H -u "$TARGET_USER" python3 -B "$USER_STAGE/rebuild_tools.py" check-checkout \
        --home "$TARGET_HOME" --work "$USER_STAGE/source-check" --project "$name" <"$RECIPE"
      changes=$("${project_git[@]}" status --porcelain --untracked-files=all)
      [ -z "$changes" ] || { status ERROR "Project changed during restore: $subdir"; exit 1; }
      head=$("${project_git[@]}" rev-parse HEAD)
      if [ "$head" != "$revision" ]; then
        transaction save "$TARGET_HOME/$subdir"
        "${project_git[@]}" fetch --quiet --no-tags "$USER_STAGE/$name" "$revision"
        "${project_git[@]}" merge --ff-only --no-edit FETCH_HEAD
      fi
    else
      transaction save "$TARGET_HOME/$subdir"
      cp -a -- "$WORK_DIR/$name" "$TARGET_HOME/$subdir"
      chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/$subdir"
    fi
  elif [ "$name" = research_workflow ]; then
    python3 -B "$HELPER" authority-state "$WORK_DIR/$name" "$TARGET_HOME/$subdir" >"$WORK_DIR/authority-recheck.json" || { cat "$WORK_DIR/authority-recheck.json" >&2; exit 1; }
    authority_state=$(python3 -B -c 'import json,sys;print(json.load(open(sys.argv[1]))["state"])' "$WORK_DIR/authority-recheck.json")
    deploy_tree "$WORK_DIR/$name" "$TARGET_HOME/$subdir" "$TARGET_USER:$TARGET_USER" --exclude-path metadata --exclude-path policy
    if [ "$authority_state" = empty ]; then
      for directory in metadata policy; do
        preserve_path "$TARGET_HOME/$subdir/$directory"
        cp -a -- "$WORK_DIR/$name/$directory" "$TARGET_HOME/$subdir/$directory"
        chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/$subdir/$directory"
      done
    fi
  else
    deploy_tree "$WORK_DIR/$name" "$TARGET_HOME/$subdir" "$TARGET_USER:$TARGET_USER"
  fi
  set_result "$name" verified 'Selected project deployed; device identity retained. Full framework acceptance remains separate.'
  if [ "$name" = research_workflow ] && [ ! -f "$TARGET_HOME/$subdir/workspace.toml" ]; then
    set_result research_workflow uncovered 'Project cloned. Initialize this device identity and local paths before Research_Workflow use; desktop-1 settings were not copied.'
  fi
done
if [ -d "$WORK_DIR/home" ]; then
  CURRENT_COMPONENT=home
  subtask 'Deploy home configuration'
  deploy_tree "$WORK_DIR/home" "$TARGET_HOME" "$TARGET_USER:$TARGET_USER"
  set_result home verified 'Selected home file contents and metadata match.'
fi
if [ -d "$WORK_DIR/credentials" ]; then
  CURRENT_COMPONENT=credentials
  subtask 'Deploy selected credentials'
  deploy_tree "$WORK_DIR/credentials" "$TARGET_HOME" "$TARGET_USER:$TARGET_USER" "${CREDENTIAL_EXCLUDES[@]}"
  set_result credentials unverified 'Selected direct credentials match; chosen Stow-managed effective files await final checks.'
fi

CURRENT_COMPONENT=dot_files
status 5/8 'Preflight and deploy the restored Stow packages.'
if [ -d "$WORK_DIR/dot_files" ]; then
  subtask 'Compare and deploy managed Stow links'
  python3 -B "$HELPER" stow "$TARGET_HOME/dot_files" "$TARGET_HOME" "$RESTORE_BACKUP_DIR" "$TARGET_USER"
  set_result dot_files verified 'Published configuration and managed Stow links deployed.'
else status SKIP 'No dot_files selected.'; fi
if [ -d "$WORK_DIR/credentials" ]; then set_result credentials verified 'File contents, modes and selected Stow targets match; SSH login and GPG key use are untested.'; fi


status 6/8 'Install staged tools and validate the editor.'
if [ "$SET_FORMAT" = 2 ]; then
  if [ -d "$USER_STAGE/topiary" ]; then
    CURRENT_COMPONENT=topiary
    subtask 'Install Topiary and the pinned Nu grammar'
    preserve_path /usr/local/bin/topiary
    install -m 755 -- "$USER_STAGE/topiary/bin/topiary" /usr/local/bin/topiary
    grammar="$TARGET_HOME/.cache/topiary/nu/$TOPIARY_NU_REVISION/grammar.so"
    transaction parents "$(dirname "$grammar")"
    preserve_path "$grammar"
    install -m 755 -o "$TARGET_USER" -g "$TARGET_USER" -- "$USER_STAGE/topiary/grammar/nu.so" "$grammar"
    set_result topiary verified 'Pinned source rebuilt; version checked. Nu formatting is checked with the editor.'
  fi
  if [ -d "$USER_STAGE/rayfile" ]; then
    CURRENT_COMPONENT=rayfile
    subtask 'Install the verified Rayfile client'
    sudo -H -u "$TARGET_USER" env ARCH_RESTORE_TRANSACTION="$USER_STAGE/transaction" python3 -B - "$USER_STAGE" "$TARGET_HOME" <<'PY_RAYFILE_DOWNLOAD'
import sys
from pathlib import Path
sys.path.insert(0,sys.argv[1])
import rayfile_state
rayfile_state.deploy(Path(sys.argv[1])/'rayfile',Path(sys.argv[2]),replace=True)
PY_RAYFILE_DOWNLOAD
    set_result rayfile verified 'Pinned official archive and binary matched; client --version passed.'
  fi
fi
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
  subtask 'Check legacy Topiary runtime dependencies'
  topiary_probe "$WORK_DIR/topiary/bin/topiary" dependencies >"$WORK_DIR/topiary-target-dependencies.txt"
  python3 -IB - "$WORK_DIR/topiary/runtime.json" "$WORK_DIR/topiary-target-dependencies.txt" "$WORK_DIR/topiary-target-runtime.json" "$SRC_DIR" <<'PY_TOPIARY_CHECK'
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
  [ ! -d "$WORK_DIR/nvim" ] || cp -a -- "$WORK_DIR/nvim" "$USER_STAGE/"
  [ ! -d "$WORK_DIR/rayfile" ] || cp -a -- "$WORK_DIR/rayfile" "$USER_STAGE/"
  if [ -f "$WORK_DIR/rebuild/editor_tools.json" ]; then cp -- "$WORK_DIR/rebuild/editor_tools.json" "$USER_STAGE/editor_tools.json"; fi
  chown -R "$TARGET_USER:$TARGET_USER" "$USER_STAGE"
fi
if [ "$NVIM_READY" = true ]; then
  CURRENT_COMPONENT=mason_tools
  subtask 'Check and rebuild pinned Mason tools'
  if [ ! -f "$USER_STAGE/editor_tools.json" ]; then
    status ERROR 'Editor tool reconstruction metadata is missing; exact Mason recovery cannot proceed.'
    exit 1
  fi
  sudo -H -u "$TARGET_USER" env ARCH_RESTORE_TRANSACTION="$USER_STAGE/transaction" python3 -B "$USER_STAGE/nvim_state.py" --home "$TARGET_HOME" \
    mason-restore "$USER_STAGE/editor_tools.json" "$USER_STAGE/nvim" "$USER_STAGE/nvim_plugins.lua" --json >"$WORK_DIR/mason-preview.json"
  mason_identity=$(python3 -B -c 'import json,sys;v=json.load(open(sys.argv[1]));assert v["status"]=="preview";print(v["identity"])' "$WORK_DIR/mason-preview.json")
  sudo -H -u "$TARGET_USER" env "${TOOL_PROXY_ENV[@]}" ARCH_RESTORE_TRANSACTION="$USER_STAGE/transaction" python3 -B "$USER_STAGE/nvim_state.py" --home "$TARGET_HOME" \
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
  subtask 'Validate the editor and its integrations'
  sudo -H -u "$TARGET_USER" env ARCH_RESTORE_TRANSACTION="$USER_STAGE/transaction" python3 -B "$USER_STAGE/nvim_state.py" --home "$TARGET_HOME" equivalent "$USER_STAGE/nvim" --json >"$WORK_DIR/nvim-equivalent.json"
  equivalent=$(python3 -B -c 'import json,sys;print("true" if json.load(open(sys.argv[1]))["equivalent"] else "false")' "$WORK_DIR/nvim-equivalent.json")
  if [ "$equivalent" = true ]; then
    generation=$(python3 -B -c 'import json,sys;print(json.load(open(sys.argv[1]))["generation"])' "$WORK_DIR/nvim-equivalent.json")
    sudo -H -u "$TARGET_USER" env ARCH_RESTORE_TRANSACTION="$USER_STAGE/transaction" python3 -B "$USER_STAGE/nvim_state.py" --home "$TARGET_HOME" validate "$generation" --json >"$WORK_DIR/nvim-result.json"
    status SKIP 'The active generation has identical payload content; no generation or activation change.'
  else
    sudo -H -u "$TARGET_USER" env ARCH_RESTORE_TRANSACTION="$USER_STAGE/transaction" python3 -B "$USER_STAGE/nvim_state.py" --home "$TARGET_HOME" \
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
    sudo -H -u "$TARGET_USER" env ARCH_RESTORE_TRANSACTION="$USER_STAGE/transaction" python3 -B "$USER_STAGE/nvim_state.py" --home "$TARGET_HOME" activate "$generation" --expect-identity "$identity" --run --json
  fi
  set_result nvim verified 'Active config/runtime/plugins/parsers match the selected payload and passed current dependency validation.'
else
  set_result jukit_core uncovered 'Core system packages installed, but no offline-ready Neovim snapshot is available for end-to-end acceptance.'
  set_result mason_tools uncovered 'No validated staged editor/Mason runtime is available for exact tool reconstruction.'
fi
if [ "$RAYFILE_READY" = true ]; then
  CURRENT_COMPONENT=rayfile
  subtask 'Verify or restore the Rayfile client'
  sudo -H -u "$TARGET_USER" python3 -B "$USER_STAGE/backup_set.py" rayfile-equivalent "$USER_STAGE/rayfile" "$TARGET_HOME" "$USER_STAGE/rayfile_state.py" >"$WORK_DIR/rayfile-equivalent.json"
  if python3 -B -c 'import json,sys;raise SystemExit(0 if json.load(open(sys.argv[1]))["equivalent"] else 1)' "$WORK_DIR/rayfile-equivalent.json"; then
    sudo -H -u "$TARGET_USER" env ARCH_RESTORE_TRANSACTION="$USER_STAGE/transaction" python3 -B "$USER_STAGE/rayfile_state.py" verify --home "$TARGET_HOME"
    status SKIP 'Rayfile managed runtime bytes, permissions and launcher already match; no replacement or safety copy.'
  else
    sudo -H -u "$TARGET_USER" env ARCH_RESTORE_TRANSACTION="$USER_STAGE/transaction" python3 -B "$USER_STAGE/rayfile_state.py" restore "$USER_STAGE/rayfile" --home "$TARGET_HOME"
  fi
  set_result rayfile verified 'Managed runtime and launcher content/permissions checked; --version succeeded; transfers/resume remain unverified.'
fi

CURRENT_COMPONENT=formatter_linter_tools
if [ -f "$WORK_DIR/rebuild/editor_tools.json" ] && python3 -B -c 'import json,sys;raise SystemExit(0 if "formatter_linter_tools" in json.load(open(sys.argv[1])) else 1)' "$WORK_DIR/rebuild/editor_tools.json"; then
  subtask 'Check recorded formatters and linters'
  cp -- "$WORK_DIR/rebuild/editor_tools.json" "$USER_STAGE/formatter-tools.json"
  chown "$TARGET_USER:$TARGET_USER" "$USER_STAGE/formatter-tools.json"
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

status 7/8 'Restore the default shell.'
if [ -f "$WORK_DIR/packages/default_shell.txt" ]; then
  CURRENT_COMPONENT=packages
  subtask 'Check the recorded login shell'
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
      chsh -s "$shell_path" "$TARGET_USER"
    fi
    set_result packages verified 'Package transactions, four Arch editor dependencies and selected default shell checked.'
  else
    status ERROR 'Recorded shell is unavailable or invalid; rolling back managed files.'
    exit 1
  fi
elif [ -n "$SET_DIR" ]; then
  status ERROR 'The selected set lacks its default-shell record.'
  exit 1
else
  subtask 'No legacy login shell recorded' SKIP
fi
if [ -d "$WORK_DIR/rebuild" ]; then
  set_result rebuild verified 'Source/version records consumed from the selected set; no extra recovery directory.'
  set_result private_npm uncovered 'Private npm installation is outside this recovery; recorded names remain in the backup.'
fi
status 8/8 'Finish and clean invocation staging.'
CURRENT_COMPONENT=""
if [ -n "$LEGACY_DIR" ]; then
  RESTORE_OUTCOME=legacy
  status WARN 'Legacy recovery ended with unproven batch consistency; see per-component omissions.'
  exit 3
fi
RESTORE_OUTCOME=finished
printf 'Selected recovery operations finished. Per-component evidence and limits follow.\n'
status SKIP 'No commits, pushes or cleanup of previous runs.'
