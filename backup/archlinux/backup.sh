#!/usr/bin/env bash

set -e
set -o pipefail
# Keep passphrases out of shell traces.
set +x

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
DOTFILES_DIR="$HOME/dot_files"
SCRIPTS_DIR="$HOME/scripts"
WORKFLOW_DIR="$HOME/Research_Workflow"
SET_ROOT="$SCRIPT_DIR/data"
HELPER="$SCRIPT_DIR/backup_set.py"
PREVIEW=false
CORE_ARCH_PACKAGES=(python-pynvim ipython python-matplotlib python-pylatexenc)
TOPIARY_NU_REVISION=18b7f951e0c511f854685dfcc9f6a34981101dd6
TOPIARY_NU_SHA256=6507a874e74108a380a043daefffc71ed3ead75beb46101df21f0792800cdad1

COLOR=false
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then COLOR=true; fi
status() {
  local label=$1 message=$2 color=36
  case "$label" in OK) color=32 ;; WARN|SKIP) color=33 ;; ERROR) color=31 ;; esac
  if [ "$label" = ERROR ]; then
    if [ "$COLOR" = true ]; then printf '\033[%sm[%s]\033[0m %s\n' "$color" "$label" "$message" >&2
    else printf '[%s] %s\n' "$label" "$message" >&2; fi
  elif [ "$COLOR" = true ]; then printf '\033[%sm[%s]\033[0m %s\n' "$color" "$label" "$message"
  else printf '[%s] %s\n' "$label" "$message"; fi
}
field() { printf '%s: %s\n' "$1" "$2"; }
step() { status "$1" "$2"; }
usage() {
  printf '%s\n' "Usage: $0 [--preview]" "" \
    "Publish one verified Arch backup to data/github-current for Git." "" \
    "Options:" "  --preview  Show scope without reading credentials or creating files." \
    "  -h, --help Show this help." "" "Example: bash backup/archlinux/backup.sh --preview"
}
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --preview) PREVIEW=true ;;
    *) status ERROR "Unknown argument: $arg."; usage >&2; exit 2 ;;
  esac
done
if [ "$COLOR" = true ]; then printf '\n\033[36mArch Linux WSL backup\033[0m\n'
else printf '\nArch Linux WSL backup\n'; fi
field Target "$SET_ROOT/github-current"
field Mode "$([ "$PREVIEW" = true ] && printf preview || printf run)"
field Rule 'replace the current set atomically only after all checks pass'
field Components 'system/home configuration, encrypted credentials, packages and pinned download records'
field Excluded 'project/plugin trees, binaries, Git history, workspace.toml, caches and research data'
field 'Editor core' "${CORE_ARCH_PACKAGES[*]}; /usr/bin/python3 and /usr/bin/ipython3, no ~/base environment"
field Restore 'current set; automatic scoped replacement, rollback and temporary cleanup'
if [ "$PREVIEW" = true ]; then
  status DRY-RUN 'No credentials, client, package manager or archive operations; no files created.'
  exit 0
fi

umask 077
unset GPG_PASS GPG_CONFIRM
for command in python3 tar gpg gpgconf pacman getent flock git; do
  command -v "$command" >/dev/null || { status ERROR "Missing command: $command."; exit 1; }
done
for directory in "$DOTFILES_DIR" "$SCRIPTS_DIR" "$WORKFLOW_DIR"; do
  [ -d "$directory" ] && [ ! -L "$directory" ] || { status ERROR "Missing regular source directory: $directory."; exit 1; }
done
python3 -B "$HELPER" parents "$SET_ROOT"
mkdir -p -- "$SET_ROOT"
exec 8<"$SET_ROOT"
flock -xn 8 || { status ERROR 'Another backup is running.'; exit 1; }
SET_DIR=""
SET_ID=""
WORK_DIR=""
WORK_ID=""
GPG_ROOT=""
GPG_ROOT_ID=""
GPG_HOME_ID=""
GPG_HOME=""
ensure_crypto_home() {
  if [ -z "$GPG_ROOT" ]; then
    IFS=$'\t' read -r GPG_ROOT GPG_ROOT_ID < <(python3 -IB "$SCRIPT_DIR/backup_crypto.py" start) || return 1
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
    if ! CODEX_TEMP_CLEANUP=1 python3 -IB "$SCRIPT_DIR/backup_crypto.py" close "$path" "$GPG_ROOT_ID"; then
      status ERROR "Private crypto directory retained for review: $path"
      return 1
    fi
  fi
}
cleanup_backup_tmp() {
  local failed=0
  unset GPG_PASS GPG_CONFIRM
  stop_crypto_agent || failed=1
  if [ -n "$WORK_DIR" ]; then
    if CODEX_TEMP_CLEANUP=1 python3 -B "$HELPER" cleanup "$WORK_DIR" "$WORK_ID"; then WORK_DIR=""
    else status ERROR "Could not clean owned plaintext staging: $WORK_DIR"; failed=1; fi
  fi
  return "$failed"
}
finish_backup() {
  local code=$?
  trap - EXIT
  cleanup_backup_tmp || code=1
  if [ -n "$SET_ID" ]; then
    CODEX_TEMP_CLEANUP=1 python3 -B "$HELPER" cleanup "$SET_DIR" "$SET_ID" || code=1
  fi
  exit "$code"
}
trap finish_backup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
SET_DIR=$(python3 -B "$HELPER" init "$SET_ROOT")
SET_ID=$(python3 -B "$HELPER" temp-id "$SET_DIR")
IFS=$'\t' read -r WORK_DIR WORK_ID < <(python3 -B "$HELPER" temp-create arch-backup.)
record() { python3 -B "$HELPER" record "$SET_DIR" "$@"; }
archive_tree() {
  local name=$1 source=$2 encrypted=${3:-false} output
  local synthetic=() path
  case "$name" in
    system) synthetic=(etc etc/pacman.d) ;;
    credentials) synthetic=(.config .config/rclone .codex) ;;
  esac
  local catalog_args=()
  for path in "${synthetic[@]}"; do
    [ ! -d "$source/$path" ] || catalog_args+=(--synthetic-directory "$path")
  done
  python3 -B "$HELPER" catalog "$source" "${catalog_args[@]}"
  output="$WORK_DIR/$name.tar.gz"
  tar --hard-dereference -czf "$output" -C "$source" .
  python3 -B "$HELPER" inspect "$output" --require-catalog >/dev/null
  if [ "$encrypted" = true ]; then
    ensure_crypto_home
    printf '%s\n' "$GPG_PASS" | gpg --homedir "$GPG_HOME" --no-options --no-symkey-cache --batch --pinentry-mode loopback --passphrase-fd 0 \
      --symmetric --cipher-algo AES256 --output "$SET_DIR/$name.tar.gz.gpg" "$output"
    record "$name" --file "$name.tar.gz.gpg"
  else
    cp -- "$output" "$SET_DIR/$name.tar.gz"
    record "$name" --file "$name.tar.gz"
  fi
}
step 1/6 'Check published sources and record package names, exact observed versions and default shell.'
mkdir "$WORK_DIR/rebuild"
python3 -B "$SCRIPT_DIR/rebuild_tools.py" capture --home "$HOME" --work "$WORK_DIR/source-check" >"$WORK_DIR/rebuild/downloads.json"
mkdir "$WORK_DIR/packages"
pacman -Qqen >"$WORK_DIR/packages/pkglist-pacman.txt"
pacman -Qqem >"$WORK_DIR/packages/pkglist-aur.txt"
pacman -Q >"$WORK_DIR/packages/versions.txt"
pacman -Q "${CORE_ARCH_PACKAGES[@]}" >"$WORK_DIR/packages/jukit-core-versions.txt"
getent passwd "$(id -un)" | cut -d: -f7 >"$WORK_DIR/packages/default_shell.txt"
archive_tree packages "$WORK_DIR/packages"

step 2/6 'Archive selected system and home configuration.'
mkdir "$WORK_DIR/system" "$WORK_DIR/home"
for path in etc/pacman.conf etc/pacman.d/mirrorlist etc/makepkg.conf etc/wsl.conf etc/locale.conf etc/fstab; do
  if [ -e "/$path" ]; then
    [ -f "/$path" ] && [ ! -L "/$path" ] || { status ERROR "Unsupported system source: /$path"; exit 1; }
    mkdir -p "$WORK_DIR/system/$(dirname "$path")"; cp -p -- "/$path" "$WORK_DIR/system/$path"
  fi
done
for path in .bashrc .bash_profile .bash_logout AGENTS.md; do
  if [ -e "$HOME/$path" ]; then cp -L -p -- "$HOME/$path" "$WORK_DIR/home/$path"; fi
done
archive_tree system "$WORK_DIR/system"
archive_tree home "$WORK_DIR/home"

step 3/6 'Encrypt credentials.'
[ -t 0 ] || { status ERROR 'Credential backup requires a local terminal for hidden passphrase input.'; exit 1; }
read -r -s -p 'GPG passphrase: ' GPG_PASS
printf '\n'
[ -n "$GPG_PASS" ] || { status ERROR 'Empty passphrase refused.'; exit 1; }
read -r -s -p 'Confirm the backup GPG passphrase: ' GPG_CONFIRM
printf '\n'
[ "$GPG_PASS" = "$GPG_CONFIRM" ] || { status ERROR 'Passphrases differ; no sensitive component was archived.'; exit 1; }
unset GPG_CONFIRM
mkdir "$WORK_DIR/credentials"
# Copy durable credentials only; never archive a whole runtime directory.
python3 -B - "$HOME" "$WORK_DIR/credentials" <<'PY_CREDENTIALS'
from pathlib import Path
import re,shutil,sys
home,dest=map(Path,sys.argv[1:]);selected=set()
for directory in ('.ssh','.gnupg'):
 if (home/directory).is_symlink():raise SystemExit('Linked credential directory refused: '+directory)
ssh=home/'.ssh'
for name in ('known_hosts','authorized_keys'):
 if (ssh/name).is_file():selected.add(ssh/name)
for key in ssh.glob('id_*'):
 if key.is_file() and key.suffix in ('','.pub'):selected.add(key)
for public in ssh.glob('*.pub'):
 private=public.with_suffix('')
 if private.is_file():selected.update((private,public))
gpg=home/'.gnupg'
for name in ('pubring.kbx','pubring.gpg','secring.gpg','trustdb.gpg','tofu.db','gpg.conf','gpg-agent.conf','dirmngr.conf','common.conf','sshcontrol'):
 if (gpg/name).is_file():selected.add(gpg/name)
for directory,suffix in (('private-keys-v1.d','key'),('openpgp-revocs.d','rev')):
 for key in (gpg/directory).glob('*.'+suffix):
  if re.fullmatch(r'(?:[0-9A-Fa-f]{40}|[0-9A-Fa-f]{64})\.'+suffix,key.name):selected.add(key)
if (gpg/'public-keys.d/pubring.db').exists():
 raise SystemExit('Keyboxd database requires a consistent export; no live database or WAL files will be archived.')
for source in sorted(selected):
 if source.is_symlink() or not source.resolve().is_relative_to(home.resolve()):raise SystemExit('Linked credential source refused: '+str(source))
 target=dest/source.relative_to(home);target.parent.mkdir(parents=True,exist_ok=True)
 shutil.copy2(source,target)
PY_CREDENTIALS
for path in .config/rclone/rclone.conf .codex/.env .gitconfig; do
  if [ -e "$HOME/$path" ]; then
    source=$(realpath "$HOME/$path")
    case "$path:$source" in
      ".config/rclone/rclone.conf:$HOME/.config/rclone/rclone.conf"|".config/rclone/rclone.conf:$DOTFILES_DIR/rclone/.config/rclone/rclone.conf"|\
      ".codex/.env:$HOME/.codex/.env"|".gitconfig:$HOME/.gitconfig"|".gitconfig:$DOTFILES_DIR/git/.gitconfig") ;;
      *) status ERROR "Review the linked source before backing up $path."; exit 1 ;;
    esac
    [ -f "$source" ] || { status ERROR "Not a regular credential source: $path"; exit 1; }
    mkdir -p "$WORK_DIR/credentials/$(dirname "$path")"
    cp -L -- "$source" "$WORK_DIR/credentials/$path"; chmod 600 "$WORK_DIR/credentials/$path"
  fi
done
archive_tree credentials "$WORK_DIR/credentials" true
unset GPG_PASS
for component in scripts dot_files research_workflow nvim topiary rayfile; do
  record "$component" --absent 'No snapshot; downloads.json records selected published sources or source absence.'
done

step 4/6 'Record core editor tool versions and sources.'
python3 -B "$SCRIPT_DIR/nvim_state.py" --home "$HOME" tools --sources-only --json >"$WORK_DIR/rebuild/editor_tools.json"
archive_tree rebuild "$WORK_DIR/rebuild"
step 5/6 'Verify all component hashes and publish the completion marker.'
python3 -B "$HELPER" seal "$SET_DIR" >/dev/null
cleanup_backup_tmp
step 6/6 'Publish the verified component files for Git.'
python3 -B "$HELPER" publish "$SET_DIR"
SET_ID=""
status OK "Complete backup set: $SET_ROOT/github-current (ID: ${SET_DIR##*/})"
status SKIP 'Commit and push the recovery scripts and data/github-current together when ready.'
