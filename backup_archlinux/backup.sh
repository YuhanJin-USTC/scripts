#!/bin/bash

set -e
set -o pipefail

DOTFILES_DIR="$HOME/dot_files"
SCRIPTS_DIR="$HOME/scripts"
BACKUP_ROOT="$SCRIPTS_DIR/backup_archlinux"
PKG_LIST_DIR="$BACKUP_ROOT/pkg-lists"
DATA_DIR="$BACKUP_ROOT/data"

mkdir -p "$PKG_LIST_DIR" "$DATA_DIR"

echo "=== Arch Linux WSL Backup Pipeline ==="

echo "[1/8] Backup pkgs from pacman..."
pacman -Qqen >"$PKG_LIST_DIR/pkglist-pacman.txt" || true

echo "[2/8] Backup pkgs from AUR..."
pacman -Qqem >"$PKG_LIST_DIR/pkglist-aur.txt" || true

if grep -q "^topiary$" "$PKG_LIST_DIR/pkglist-aur.txt"; then
  sed -i 's/^topiary$/topiary-bin/' "$PKG_LIST_DIR/pkglist-aur.txt"
  echo "  -> Replaced 'topiary' with 'topiary-bin' to avoid slow compilation."
fi

echo "[3/8] Archive sensitive credentials..."
SENSITIVE_PATHS=()
[ -d "$HOME/.ssh" ] && SENSITIVE_PATHS+=(".ssh")
[ -d "$HOME/.gnupg" ] && SENSITIVE_PATHS+=(".gnupg")
[ -f "$HOME/.config/rclone/rclone.conf" ] && SENSITIVE_PATHS+=(".config/rclone/rclone.conf")
[ -f "$HOME/.codex/.env" ] && SENSITIVE_PATHS+=(".codex/.env")

if [ ${#SENSITIVE_PATHS[@]} -gt 0 ]; then
  tar --exclude=".ssh/config" -czf - -C "$HOME" "${SENSITIVE_PATHS[@]}" |
    gpg --yes --pinentry-mode loopback --symmetric --cipher-algo AES256 --output "$DATA_DIR/secure_data.tar.gz.gpg"
  echo "  -> Credentials archived to $DATA_DIR/secure_data.tar.gz.gpg"
  echo "  -> SSH config excluded; restore it from dot_files/stow."
else
  echo "  -> No credentials found to archive."
fi

echo "[4/8] Archive home shell configuration files..."
HOME_CONFIGS=()
for path in .bashrc .bash_profile .bash_logout; do
  [ -e "$HOME/$path" ] && HOME_CONFIGS+=("$path")
done

if [ ${#HOME_CONFIGS[@]} -gt 0 ]; then
  tar -czf "$DATA_DIR/home_config.tar.gz" -C "$HOME" "${HOME_CONFIGS[@]}"
  echo "  -> Home configs archived to $DATA_DIR/home_config.tar.gz"
else
  echo "  -> No home shell configs found to archive."
fi

echo "[5/8] Archive system configuration files..."
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
  echo "  -> System configs archived to $DATA_DIR/sys_config.tar.gz"
else
  echo "  -> No system configs found to archive."
fi

echo "[6/8] Archive default shell configuration..."
getent passwd "$USER" | cut -d: -f7 >"$DATA_DIR/default_shell.txt"
echo "  -> Default shell ($(cat "$DATA_DIR/default_shell.txt")) recorded."

echo "[7/8] Backup Windows WezTerm configuration..."
WIN_PROFILE_CMD=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')

if [ -n "$WIN_PROFILE_CMD" ]; then
  WIN_HOME=$(wslpath "$WIN_PROFILE_CMD")
  WEZTERM_WIN_DIR="$WIN_HOME/.config/wezterm"
  WEZTERM_DOTFILES_DIR="$DOTFILES_DIR/windows_configs/wezterm"

  if [ -d "$WEZTERM_WIN_DIR" ]; then
    mkdir -p "$DOTFILES_DIR/windows_configs"
    rm -rf "$WEZTERM_DOTFILES_DIR"
    cp -r "$WEZTERM_WIN_DIR" "$WEZTERM_DOTFILES_DIR"
    echo "  -> Copied WezTerm config directory from Windows to $WEZTERM_DOTFILES_DIR"
  else
    echo "  -> Notice: WezTerm config directory not found at $WEZTERM_WIN_DIR. Skipping."
  fi
else
  echo "  -> Warning: Failed to resolve Windows User Profile path via WSL Interop."
fi

echo "[8/8] Check git status of core directories..."
CHECK_DIRS=(
  "$DOTFILES_DIR"
  "$SCRIPTS_DIR"
  "$HOME/singularity_def_files"
)

for dir in "${CHECK_DIRS[@]}"; do
  if [ -d "$dir/.git" ]; then
    cd "$dir" || exit
    if [[ -n $(git status -s) ]]; then
      echo "  [Warning] Uncommitted changes detected in $dir."
      echo "  >>> PLEASE COMMIT AND PUSH THESE CHANGES TO PREVENT DATA LOSS <<<"
      git status -s | sed 's/^/    /'
    fi
  elif [ -d "$dir" ]; then
    echo "  [Notice] $dir is not a git repository. It will not be synced."
  fi
done

echo "=== Backup Accomplished ==="
