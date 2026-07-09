#!/bin/bash

set -e
set -o pipefail

DOTFILES_DIR="$HOME/dot_files"
SCRIPTS_DIR="$HOME/scripts"
BACKUP_ROOT="$SCRIPTS_DIR/backup_archlinux"
PKG_LIST_DIR="$BACKUP_ROOT/pkg-lists"
DATA_DIR="$BACKUP_ROOT/data"

color() {
  printf '\033[%sm%s\033[0m' "$1" "$2"
}

status_label() {
  case "$1" in
    OK) color 32 OK ;;
    SKIP) color 33 SKIP ;;
    WARN) color 33 WARN ;;
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

step() {
  printf '[%s] %s\n' "$1" "$2"
}

usage() {
  printf '%s\n' \
    "Usage: $0" \
    "" \
    "Backup Arch Linux WSL package lists, selected configs, credentials, and Git state." \
    "" \
    "Options:" \
    "  -h, --help  Show this help."
}

print_header() {
  echo ""
  color 36 "Arch Linux WSL backup"
  echo ""
  field "Target" "$BACKUP_ROOT"
  field "Mode" "run"
  field "Rule" "package lists + selected config archives"
  echo ""
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

mkdir -p "$PKG_LIST_DIR" "$DATA_DIR"

print_header

step "1/7" "Backup pkgs from pacman"
pacman -Qqen >"$PKG_LIST_DIR/pkglist-pacman.txt" || true

step "2/7" "Backup pkgs from AUR"
pacman -Qqem >"$PKG_LIST_DIR/pkglist-aur.txt" || true

if grep -q "^topiary$" "$PKG_LIST_DIR/pkglist-aur.txt"; then
  sed -i 's/^topiary$/topiary-bin/' "$PKG_LIST_DIR/pkglist-aur.txt"
  status OK "Replaced 'topiary' with 'topiary-bin' to avoid slow compilation."
fi

step "3/7" "Archive sensitive credentials"
SENSITIVE_PATHS=()
[ -d "$HOME/.ssh" ] && SENSITIVE_PATHS+=(".ssh")
[ -d "$HOME/.gnupg" ] && SENSITIVE_PATHS+=(".gnupg")
[ -f "$HOME/.config/rclone/rclone.conf" ] && SENSITIVE_PATHS+=(".config/rclone/rclone.conf")
[ -f "$HOME/.codex/.env" ] && SENSITIVE_PATHS+=(".codex/.env")

if [ ${#SENSITIVE_PATHS[@]} -gt 0 ]; then
  tar --exclude=".ssh/config" -czf - -C "$HOME" "${SENSITIVE_PATHS[@]}" |
    gpg --yes --pinentry-mode loopback --symmetric --cipher-algo AES256 --output "$DATA_DIR/secure_data.tar.gz.gpg"
  status OK "Credentials archived to $DATA_DIR/secure_data.tar.gz.gpg"
  status SKIP "SSH config excluded; restore it from dot_files/stow."
else
  status SKIP "No credentials found to archive."
fi

step "4/7" "Archive home shell configuration files"
HOME_CONFIGS=()
for path in .bashrc .bash_profile .bash_logout; do
  [ -e "$HOME/$path" ] && HOME_CONFIGS+=("$path")
done

if [ ${#HOME_CONFIGS[@]} -gt 0 ]; then
  tar -czf "$DATA_DIR/home_config.tar.gz" -C "$HOME" "${HOME_CONFIGS[@]}"
  status OK "Home configs archived to $DATA_DIR/home_config.tar.gz"
else
  status SKIP "No home shell configs found to archive."
fi

step "5/7" "Archive system configuration files"
SYS_CONFIGS=()
for path in \
  etc/pacman.conf \
  etc/pacman.d/mirrorlist \
  etc/makepkg.conf \
  etc/wsl.conf \
  etc/locale.conf \
  etc/fstab; do
  [ -e "/$path" ] && SYS_CONFIGS+=("$path")
done

if [ ${#SYS_CONFIGS[@]} -gt 0 ]; then
  tar -czf "$DATA_DIR/sys_config.tar.gz" -C / "${SYS_CONFIGS[@]}" 2>/dev/null || true
  status OK "System configs archived to $DATA_DIR/sys_config.tar.gz"
else
  status SKIP "No system configs found to archive."
fi

step "6/7" "Archive default shell configuration"
getent passwd "$USER" | cut -d: -f7 >"$DATA_DIR/default_shell.txt"
status OK "Default shell ($(cat "$DATA_DIR/default_shell.txt")) recorded."

step "7/7" "Check git status of core directories"
CHECK_DIRS=(
  "$DOTFILES_DIR"
  "$SCRIPTS_DIR"
  "$HOME/singularity_def_files"
)

for dir in "${CHECK_DIRS[@]}"; do
  if [ -d "$dir/.git" ]; then
    cd "$dir" || exit
    if [[ -n $(git status -s) ]]; then
      status WARN "Uncommitted changes detected in $dir."
      echo "    PLEASE COMMIT AND PUSH THESE CHANGES TO PREVENT DATA LOSS"
      git status -s | sed 's/^/    /'
    fi

    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
    if [ -n "$upstream" ]; then
      read -r behind ahead < <(git rev-list --left-right --count "$upstream"...HEAD)
      if [ "$ahead" -gt 0 ]; then
        status WARN "$dir has $ahead local commit(s) not pushed to $upstream."
        echo "    PUSH THESE COMMITS BEFORE RESTORING ON A NEW MACHINE"
      fi
      if [ "$behind" -gt 0 ]; then
        status SKIP "$dir is $behind commit(s) behind $upstream."
      fi
    else
      status SKIP "$dir has no upstream branch configured."
    fi
  elif [ -d "$dir" ]; then
    status SKIP "$dir is not a git repository. It will not be synced."
  fi
done

status OK "Backup accomplished."