#!/usr/bin/env bash

set -e
set -o pipefail
# Keep passphrases out of shell traces.
set +x

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
DOTFILES_DIR="$HOME/dot_files"
SCRIPTS_DIR="$HOME/scripts"
WORKFLOW_DIR="$HOME/Research_Workflow"
SET_ROOT="$SCRIPT_DIR/data/sets"
HELPER="$SCRIPT_DIR/backup_set.py"
PREVIEW=false
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
  printf '%s\n' "Usage: $0 [--preview]" "" \
    "Create a new complete Arch backup set without replacing old payloads." "" \
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
printf '\nArch Linux WSL backup\n'
field Target "$SET_ROOT/<unique UTC ID>"
field Mode "$([ "$PREVIEW" = true ] && printf preview || printf run)"
field Rule 'new set; no overwrite; publish COMPLETE after all checks'
field Components 'package names+versions, system, Bash/home AGENTS, encrypted credentials+dot_files, scripts, Research_Workflow, topiary, active Neovim, Rayfile, rebuild records'
field Excluded '.git (except Neovim plugins), old backup payloads, workspace.toml, caches/plans, Codex personal config/skills, scientific sources/data/images/models'
field 'Editor core' "${CORE_ARCH_PACKAGES[*]}; /usr/bin/python3 and /usr/bin/ipython3, no ~/base environment"
field Restore 'explicit set selection; exact differences and preservation; new users retain wheel NOPASSWD'
if [ "$PREVIEW" = true ]; then
  status DRY-RUN 'No credentials, client, package manager or archive operations; no files created.'
  exit 0
fi

umask 077
unset GPG_PASS GPG_CONFIRM
for command in python3 tar gpg gpgconf gpg-connect-agent pacman getent; do
  command -v "$command" >/dev/null || { status ERROR "Missing command: $command."; exit 1; }
done
for directory in "$DOTFILES_DIR" "$SCRIPTS_DIR" "$WORKFLOW_DIR"; do
  [ -d "$directory" ] && [ ! -L "$directory" ] || { status ERROR "Missing regular source directory: $directory."; exit 1; }
done
SET_DIR=$(python3 -B "$HELPER" init "$SET_ROOT")
WORK_DIR=""
WORK_ID=""
GPG_HOME=""
GPG_ID=""
GPG_SOCKET_DIR=""
GPG_SOCKET_ID=""
GPG_SOCKET=""
GPG_AGENT_PID=""
GPG_STARTED=false
IFS=$'\t' read -r WORK_DIR WORK_ID < <(python3 -B "$HELPER" temp-create arch-backup.)
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
cleanup_backup_tmp() {
  unset GPG_PASS GPG_CONFIRM
  stop_crypto_agent || { status ERROR "Isolated GPG cleanup failed; private staging retained: $WORK_DIR"; return 1; }
  CODEX_TEMP_CLEANUP=1 python3 -B "$HELPER" cleanup "$WORK_DIR" "$WORK_ID" || return 1
  if [ ! -f "$SET_DIR/COMPLETE" ]; then status WARN "Incomplete set retained: $SET_DIR"; fi
}
trap cleanup_backup_tmp EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
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
copy_tree() {
  local source=$1 target=$2
  shift 2
  mkdir -p "$target"
  tar --hard-dereference --exclude=.git --exclude=__pycache__ "$@" -cf - -C "$source" . |
    tar --no-same-owner --same-permissions -xf - -C "$target"
}

step 1/10 'Record package names, exact observed versions and default shell.'
mkdir "$WORK_DIR/packages"
pacman -Qqen >"$WORK_DIR/packages/pkglist-pacman.txt"
pacman -Qqem >"$WORK_DIR/packages/pkglist-aur.txt"
pacman -Q >"$WORK_DIR/packages/versions.txt"
pacman -Q "${CORE_ARCH_PACKAGES[@]}" >"$WORK_DIR/packages/jukit-core-versions.txt"
getent passwd "$(id -un)" | cut -d: -f7 >"$WORK_DIR/packages/default_shell.txt"
archive_tree packages "$WORK_DIR/packages"

step 2/10 'Export the accepted Neovim generation and managed Rayfile runtime.'
python3 -B "$SCRIPT_DIR/nvim_state.py" --home "$HOME" backup "$SET_DIR/nvim.tar.gz" --json
record nvim --file nvim.tar.gz
python3 -B "$SCRIPT_DIR/rayfile_state.py" backup "$SET_DIR/rayfile.tar.gz" --home "$HOME"
if [ -f "$SET_DIR/rayfile.tar.gz" ]; then record rayfile --file rayfile.tar.gz
else record rayfile --absent 'Managed client not installed.'; fi

step 3/10 'Archive selected system and home configuration.'
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

step 4/10 'Encrypt credential contents and the selected dot_files worktree.'
[ -t 0 ] || { status ERROR 'Credential backup requires a local terminal for hidden passphrase input.'; exit 1; }
read -r -s -p 'GPG passphrase for both encrypted components: ' GPG_PASS
printf '\n'
[ -n "$GPG_PASS" ] || { status ERROR 'Empty passphrase refused.'; exit 1; }
read -r -s -p 'Confirm the backup GPG passphrase: ' GPG_CONFIRM
printf '\n'
[ "$GPG_PASS" = "$GPG_CONFIRM" ] || { status ERROR 'Passphrases differ; no sensitive component was archived.'; exit 1; }
unset GPG_CONFIRM
mkdir "$WORK_DIR/credentials"
for path in .ssh .gnupg; do
  if [ -d "$HOME/$path" ]; then
    [ ! -L "$HOME/$path" ] || { status ERROR "Linked credential directory refused: $path"; exit 1; }
    tar --hard-dereference --exclude=.ssh/config --exclude='S.gpg-agent*' --exclude='S.dirmngr*' \
      -cf - -C "$HOME" "$path" | tar --no-same-owner --same-permissions -xf - -C "$WORK_DIR/credentials"
  fi
done
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
copy_tree "$DOTFILES_DIR" "$WORK_DIR/dot_files" --exclude=.codex --exclude=.agents --exclude=.research-workflow --exclude=backup
archive_tree dot_files "$WORK_DIR/dot_files" true
unset GPG_PASS

step 5/10 'Archive scripts worktree without Git metadata or backup payloads.'
copy_tree "$SCRIPTS_DIR" "$WORK_DIR/scripts" --exclude=backup/archlinux/data --exclude=backup/archlinux/pkg_lists \
  --exclude=.codex --exclude=.agents --exclude=.research-workflow --exclude=.cache --exclude=tmp --exclude=temp
archive_tree scripts "$WORK_DIR/scripts"

step 6/10 'Archive Research_Workflow code, skills and portable authority.'
copy_tree "$WORKFLOW_DIR" "$WORK_DIR/research_workflow" --exclude=./workspace.toml --exclude=./.research-workflow --exclude=.codex --exclude=.agents --exclude=.venv --exclude=.pytest_cache
python3 -B "$WORK_DIR/research_workflow/tools/researchctl.py" --workspace "$WORK_DIR/no-device.toml" \
  doctor --compatibility-only --store "$WORK_DIR/research_workflow/metadata/STORE.json" --json
archive_tree research_workflow "$WORK_DIR/research_workflow"

step 7/10 'Archive /usr/local/bin/topiary, the selected Nu grammar and system dependency records.'
TOPIARY=/usr/local/bin/topiary
if [ -e "$TOPIARY" ] || [ -L "$TOPIARY" ]; then
  [ -f "$TOPIARY" ] && [ ! -L "$TOPIARY" ] && [ -x "$TOPIARY" ] || { status ERROR 'Topiary must be the regular executable at /usr/local/bin/topiary.'; exit 1; }
  mkdir -p "$WORK_DIR/topiary/bin"
  cp -p -- "$TOPIARY" "$WORK_DIR/topiary/bin/topiary"
  TOPIARY_GRAMMAR="$HOME/.cache/topiary/nu/$TOPIARY_NU_REVISION/grammar.so"
  python3 -B "$HELPER" parents "$(dirname "$TOPIARY_GRAMMAR")"
  [ -f "$TOPIARY_GRAMMAR" ] && [ ! -L "$TOPIARY_GRAMMAR" ] || { status ERROR 'The selected Nu grammar cache is missing or linked; build it through the separately authorized workflow first.'; exit 1; }
  mkdir "$WORK_DIR/topiary/grammar"
  cp -p -- "$TOPIARY_GRAMMAR" "$WORK_DIR/topiary/grammar/nu.so"
  env -u LD_PRELOAD -u LD_LIBRARY_PATH LC_ALL=C ldd "$TOPIARY" >"$WORK_DIR/topiary/dependencies.txt"
  python3 -B - "$WORK_DIR/topiary" "$TOPIARY" <<'PY_TOPIARY_CAPTURE'
from pathlib import Path
import hashlib,json,os,re,stat,subprocess,sys
root=Path(sys.argv[1]);binary=Path(sys.argv[2]);dependencies=[]
def digest(path):
 with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def source(path):
 result={'manager':'unknown','reason':'No single installed Arch package owns this file.'}
 query=subprocess.run(['/usr/bin/pacman','-Qoq',str(path.resolve())],capture_output=True,text=True,env={**os.environ,'LC_ALL':'C'})
 package=query.stdout.strip()
 if query.returncode==0 and re.fullmatch(r'[a-z0-9][a-z0-9@._+:-]*',package):
  version=subprocess.run(['/usr/bin/pacman','-Q',package],capture_output=True,text=True,check=True).stdout.strip().split(maxsplit=1)
  if len(version)==2 and version[0]==package:
   metadata=subprocess.run(['/usr/bin/pacman','-Si',package],capture_output=True,text=True,env={**os.environ,'LC_ALL':'C'})
   repository=next((line.partition(':')[2].strip() for line in metadata.stdout.splitlines() if line.partition(':')[0].strip()=='Repository'),None) if metadata.returncode==0 else None
   result={'manager':'pacman','package':package,'version':version[1],'repository':repository,'official_repository':repository in ('core','extra','multilib'),'evidence':'local canonical file ownership, installed version and repository metadata'}
 return result
for line in (root/'dependencies.txt').read_text().splitlines():
 match=re.fullmatch(r'\s*(\S+)\s+=>\s+(/\S+)\s+\(0x[0-9a-f]+\)\s*',line)
 loader=re.fullmatch(r'\s*(/\S+)\s+\(0x[0-9a-f]+\)\s*',line)
 if match:name,value=match.groups();role='library'
 elif loader:value=loader[1];name=Path(value).name;role='loader'
 elif re.fullmatch(r'\s*linux-vdso\.so\.\d+\s+\(0x[0-9a-f]+\)\s*',line):continue
 else:raise SystemExit('Unresolved or unsupported Topiary dependency output.')
 path=Path(value)
 if not path.is_file():raise SystemExit('Missing Topiary system dependency.')
 dependencies.append({'name':name,'path':value,'realpath':str(path.resolve()),'sha256':digest(path),'role':role,'source':source(path)})
if not dependencies or sum(row['role']=='loader' for row in dependencies)!=1:raise SystemExit('Unsupported Topiary dynamic loader layout.')
value={'format':2,'executable':{'path':str(binary),'sha256':digest(binary),'mode':stat.S_IMODE(binary.stat().st_mode),'source':source(binary)},'dependencies':dependencies}
(root/'runtime.json').write_text(json.dumps(value,indent=2)+'\n')
PY_TOPIARY_CAPTURE
  python3 -B - "$WORK_DIR/topiary" "$TOPIARY_NU_REVISION" "$TOPIARY_NU_SHA256" "$HOME" <<'PY_TOPIARY_GRAMMAR'
from pathlib import Path
import hashlib,json,shlex,stat,sys
root=Path(sys.argv[1]);revision,expected=sys.argv[2:4];home=Path(sys.argv[4]);grammar=root/'grammar/nu.so'
sha=hashlib.sha256(grammar.read_bytes()).hexdigest()
if sha!=expected:raise SystemExit('Nu grammar differs from the accepted fixed-revision artifact; review a rebuild before backup.')
recipe=shlex.join(['env',f'XDG_CACHE_HOME={home}/.cache',f'TOPIARY_CONFIG_FILE={home}/.config/topiary/languages.ncl',f'TOPIARY_LANGUAGE_DIR={home}/.config/topiary/languages','/usr/local/bin/topiary','-C',str(home/'.config/topiary/languages.ncl'),'prefetch','nu'])
path=root/'runtime.json';value=json.loads(path.read_text())
value['grammar']={'language':'nu','repository':'https://github.com/nushell/tree-sitter-nu.git','revision':revision,'cache_path':f'.cache/topiary/nu/{revision}/grammar.so','sha256':sha,'mode':stat.S_IMODE(grammar.stat().st_mode),'tree_sitter_language_abi':15,'recipe':recipe,'validation':'accepted local build artifact; backup checks bytes and metadata, not formatter behavior'}
path.write_text(json.dumps(value,indent=2)+'\n')
PY_TOPIARY_GRAMMAR
  "$TOPIARY" --version >"$WORK_DIR/topiary/version.txt"
  archive_tree topiary "$WORK_DIR/topiary"
else record topiary --absent 'topiary not installed.'; fi

step 8/10 'Record external editor tools and private npm rebuild sources.'
mkdir "$WORK_DIR/rebuild"
python3 -B "$SCRIPT_DIR/nvim_state.py" --home "$HOME" tools --json >"$WORK_DIR/rebuild/editor_tools.json"
python3 -B - "$HOME" "$WORK_DIR/rebuild/npm.json" <<'PY'
from pathlib import Path
import json,sys
home=Path(sys.argv[1]);packages=[]
for base in (home/'.local/share/codex-wsl/npm/lib/node_modules',home/'.local/lib/node_modules'):
 if base.is_dir():
  for path in list(base.glob('*/package.json'))+list(base.glob('@*/*/package.json')):
   value=json.loads(path.read_text());name=value.get('name','unknown');version=value.get('version','unknown')
   packages.append({'name':name,'version':version,'source':f'npm:{name}@{version}'})
Path(sys.argv[2]).write_text(json.dumps({'npm':packages,'limits':'Private npm is a reconstruction record; entire Node/Python trees are not copied.'},indent=2)+'\n')
PY
archive_tree rebuild "$WORK_DIR/rebuild"
step 9/10 'Verify all component hashes and publish the completion marker.'
python3 -B "$HELPER" seal "$SET_DIR" >/dev/null
python3 -B "$HELPER" verify "$SET_DIR" >/dev/null
cleanup_backup_tmp
trap - EXIT
step 10/10 'Retain the new set for the existing scripts NAS synchronization.'
status OK "Complete backup set: $SET_DIR"
status SKIP 'No upload, Git operation or old-payload cleanup was performed.'
