#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define core directories
DOTFILES_DIR="$HOME/dot_files"
SCRIPTS_DIR="$HOME/scripts"
BACKUP_ROOT="$SCRIPTS_DIR/backup_archlinux"
PKG_LIST_DIR="$BACKUP_ROOT/pkg-lists"
DATA_DIR="$BACKUP_ROOT/data"

# Ensure backup directories exist
mkdir -p "$PKG_LIST_DIR" "$DATA_DIR"

echo "=== Arch Linux WSL Backup Pipeline ==="

echo "[1/7] Backup pkgs from pacman..."
pacman -Qqen >"$PKG_LIST_DIR/pkglist-pacman.txt" || true

echo "[2/7] Backup pkgs from AUR..."
pacman -Qqem >"$PKG_LIST_DIR/pkglist-aur.txt" || true

if grep -q "^topiary$" "$PKG_LIST_DIR/pkglist-aur.txt"; then
  sed -i 's/^topiary$/topiary-bin/' "$PKG_LIST_DIR/pkglist-aur.txt"
  echo "  -> Replaced 'topiary' with 'topiary-bin' to avoid slow compilation."
fi

echo "[3/7] Archive sensitive credentials (.ssh, .gnupg)..."
SENSITIVE_DIRS=()
[ -d "$HOME/.ssh" ] && SENSITIVE_DIRS+=(".ssh")
[ -d "$HOME/.gnupg" ] && SENSITIVE_DIRS+=(".gnupg")

if [ ${#SENSITIVE_DIRS[@]} -gt 0 ]; then
  # Added -h flag to follow symlinks and archive actual file content
  tar -czhf "$DATA_DIR/secure_data.tar.gz" -C "$HOME" "${SENSITIVE_DIRS[@]}"

  gpg --yes --pinentry-mode loopback --symmetric --cipher-algo AES256 --output "$DATA_DIR/secure_data.tar.gz.gpg" "$DATA_DIR/secure_data.tar.gz"
  rm -f "$DATA_DIR/secure_data.tar.gz"
  echo "  -> Credentials archived to $DATA_DIR/secure_data.tar.gz.gpg"
else
  echo "  -> No credentials found to archive."
fi

echo "[4/7] Archive system configuration files..."
tar -czf "$DATA_DIR/sys_config.tar.gz" -C / etc/pacman.conf etc/pacman.d/mirrorlist etc/makepkg.conf 2>/dev/null || true
echo "  -> System configs archived to $DATA_DIR/sys_config.tar.gz"

echo "[5/7] Archive default shell configuration..."
getent passwd "$USER" | cut -d: -f7 >"$DATA_DIR/default_shell.txt"
echo "  -> Default shell ($(cat "$DATA_DIR/default_shell.txt")) recorded."

echo "[6/7] Backup Windows WezTerm configuration..."
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

echo "[7/7] Check git status of core directories..."
CHECK_DIRS=(
  "$DOTFILES_DIR"
  "$SCRIPTS_DIR"
  "$HOME/Code_Program"
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
