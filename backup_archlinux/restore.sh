#!/bin/bash

set -e
set -o pipefail

TARGET_USER="yuhanjin"
TARGET_HOME="/home/$TARGET_USER"
DOTFILES_REPO="https://github.com/YuhanJin-USTC/dot_files.git"
SCRIPTS_REPO="https://github.com/YuhanJin-USTC/scripts.git"

PROXY_URL="http://127.0.0.1:7890"
SOCKS_URL="socks5://127.0.0.1:7890"
RESTORE_STAMP=$(date +%Y%m%d_%H%M%S)
RESTORE_BACKUP_DIR="/root/arch_restore_backup_$RESTORE_STAMP"

backup_existing_path() {
  local target=$1
  local rel
  local backup_target

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    return
  fi

  rel=${target#/}
  backup_target="$RESTORE_BACKUP_DIR/$rel"
  mkdir -p "$(dirname "$backup_target")"
  mv "$target" "$backup_target"
  echo "  -> Existing $target moved to $backup_target"
}

backup_existing_from_tar() {
  local archive=$1
  local base=$2
  local entry
  local clean_entry

  while IFS= read -r entry; do
    clean_entry=${entry#./}
    clean_entry=${clean_entry%/}
    [ -z "$clean_entry" ] && continue
    [ "$clean_entry" = ".ssh/config" ] && continue
    backup_existing_path "$base/$clean_entry"
  done < <(tar -tzf "$archive")
}

restore_sensitive_file() {
  local archive=$1
  local rel_path=$2
  local mode=$3
  local target="$TARGET_HOME/$rel_path"

  if ! tar -tzf "$archive" "$rel_path" >/dev/null 2>&1; then
    return
  fi

  backup_existing_path "$target"
  mkdir -p "$(dirname "$target")"
  tar -xOzf "$archive" "$rel_path" >"$target"
  chown "$TARGET_USER:$TARGET_USER" "$target"
  chmod "$mode" "$target"
  echo "  -> Restored $target"
}

if [ "$EUID" -ne 0 ]; then
  echo "Error: This restore pipeline MUST be executed as root."
  exit 1
fi

echo "=== Arch Linux WSL Restore Pipeline ==="

SCRIPT_DIR=$(dirname "$(realpath "$0")")
if [ -d "$SCRIPT_DIR/data" ]; then
  BACKUP_ROOT="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/backup_archlinux/data" ]; then
  BACKUP_ROOT="$SCRIPT_DIR/backup_archlinux"
else
  echo "Error: Cannot locate backup data directory."
  exit 1
fi
echo "  -> Resolved BACKUP_ROOT: $BACKUP_ROOT"

echo "[0/10] Restore system configurations..."
if [ -f "$BACKUP_ROOT/data/sys_config.tar.gz" ]; then
  backup_existing_from_tar "$BACKUP_ROOT/data/sys_config.tar.gz" /
  tar -xzf "$BACKUP_ROOT/data/sys_config.tar.gz" -C /
  echo "  -> System configs restored."
else
  echo "  -> Warning: sys_config.tar.gz not found. Skipping."
fi

echo "[1/10] Configure System Locale (UTF-8)..."
if grep -q "^#en_US.UTF-8 UTF-8" /etc/locale.gen; then
  sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  locale-gen
  echo "LANG=en_US.UTF-8" >/etc/locale.conf
  echo "  -> Locale generated and set to en_US.UTF-8."
else
  echo "  -> Locale already configured."
fi

echo "[2/10] Initialize keyring and basic pkgs..."
if [ ! -d "/etc/pacman.d/gnupg" ]; then
  pacman-key --init
  pacman-key --populate archlinux
  echo "  -> Pacman keyring initialized."
else
  echo "  -> Pacman keyring already exists. Skipping initialization."
fi
pacman -Sy --noconfirm archlinux-keyring
pacman -Su --noconfirm
pacman -S --needed --noconfirm base-devel git stow sudo wget tar openssh gnupg

echo "[3/10] Setup target user ($TARGET_USER) and privileges..."
if ! id "$TARGET_USER" &>/dev/null; then
  useradd -m -G wheel -s /bin/bash "$TARGET_USER"
  echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >/etc/sudoers.d/wheel_nopasswd
fi

if [ ! -f /etc/wsl.conf ]; then
  cat <<EOF >/etc/wsl.conf
[user]
default=$TARGET_USER
EOF
elif ! grep -q "^\[user\]" /etc/wsl.conf; then
  cat <<EOF >>/etc/wsl.conf

[user]
default=$TARGET_USER
EOF
fi

echo "[4/10] Migrate restore scripts and data..."
if [[ "$BACKUP_ROOT" != "$TARGET_HOME"* ]]; then
  echo "  -> Migrating repository to $TARGET_HOME..."
  TARGET_BACKUP_ROOT="$TARGET_HOME/backup_archlinux"
  cp -r "$BACKUP_ROOT" "$TARGET_BACKUP_ROOT"
  chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_BACKUP_ROOT"
  BACKUP_ROOT="$TARGET_BACKUP_ROOT"
fi

echo "[-] Restore home shell configurations..."
if [ -f "$BACKUP_ROOT/data/home_config.tar.gz" ]; then
  backup_existing_from_tar "$BACKUP_ROOT/data/home_config.tar.gz" "$TARGET_HOME"
  tar -xzf "$BACKUP_ROOT/data/home_config.tar.gz" -C "$TARGET_HOME"
  chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME"/.bash* 2>/dev/null || true
  echo "  -> Home shell configs restored."
else
  echo "  -> Notice: home_config.tar.gz not found. Skipping."
fi

echo "[5/10] Restore sensitive credentials (SSH & GPG)..."
if [ -f "$BACKUP_ROOT/data/secure_data.tar.gz.gpg" ]; then
  echo -n "  -> Enter GPG passphrase for credential decryption: "
  read -s GPG_PASS
  echo ""

  SECURE_TMP_DIR=$(mktemp -d)
  SECURE_TAR_TMP="$SECURE_TMP_DIR/secure_data.tar.gz"
  cleanup_secure_tmp() {
    rm -f "$SECURE_TAR_TMP"
    rmdir "$SECURE_TMP_DIR" 2>/dev/null || true
  }
  trap cleanup_secure_tmp EXIT

  if echo "$GPG_PASS" | gpg --yes --batch --pinentry-mode loopback --passphrase-fd 0 --decrypt --output "$SECURE_TAR_TMP" "$BACKUP_ROOT/data/secure_data.tar.gz.gpg"; then
    while IFS= read -r entry; do
      clean_entry=${entry#./}
      clean_entry=${clean_entry%/}
      [ -z "$clean_entry" ] && continue
      [ "$clean_entry" = ".ssh/config" ] && continue
      [ "$clean_entry" = ".config/rclone/rclone.conf" ] && continue
      [ "$clean_entry" = ".codex/.env" ] && continue
      backup_existing_path "$TARGET_HOME/$clean_entry"
    done < <(tar -tzf "$SECURE_TAR_TMP")

    tar \
      --exclude=".ssh/config" \
      --exclude=".config/rclone/rclone.conf" \
      --exclude=".codex/.env" \
      -xzf "$SECURE_TAR_TMP" -C "$TARGET_HOME/"

    chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh" "$TARGET_HOME/.gnupg" 2>/dev/null || true
    chmod 700 "$TARGET_HOME/.ssh" "$TARGET_HOME/.gnupg" 2>/dev/null || true
    find "$TARGET_HOME/.ssh" -type f -exec chmod 600 {} \; 2>/dev/null || true
    find "$TARGET_HOME/.ssh" -type f -name "*.pub" -exec chmod 644 {} \; 2>/dev/null || true
    echo "  -> SSH/GPG restored; SSH config left for dot_files/stow."
  else
    echo "  -> Error: Decryption failed. Skipping Step [5/10]."
  fi
else
  echo "  -> No secure data archive found. Skipping."
fi

echo "[6/10] Install pkgs from pacman..."
PKG_LIST_DIR="$BACKUP_ROOT/pkg-lists"
if [ -f "$PKG_LIST_DIR/pkglist-pacman.txt" ]; then
  pacman -S --needed --noconfirm - <"$PKG_LIST_DIR/pkglist-pacman.txt"
else
  echo "  -> Error: pkglist-pacman.txt not found."
fi

echo "[7/10] Deploy AUR helper (yay)..."
su -s /bin/bash "$TARGET_USER" <<EOF
set -e
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export all_proxy="$SOCKS_URL"

if ! command -v yay &>/dev/null; then
  echo "  -> Installing yay via proxy..."
  rm -rf /tmp/yay  
  git clone https://aur.archlinux.org/yay-bin.git /tmp/yay
  cd /tmp/yay
  makepkg -si --noconfirm
  rm -rf /tmp/yay
else
  echo "  -> yay is already installed."
fi
EOF

echo "[8/10] Install pkgs from AUR..."
if [ -f "$PKG_LIST_DIR/pkglist-aur.txt" ]; then
  AUR_PKGS=$(grep -v '^#' "$PKG_LIST_DIR/pkglist-aur.txt" | grep -vwE 'yay|yay-bin' | tr '\n' ' ' | xargs)

  if [ -n "$AUR_PKGS" ]; then
    sudo -u "$TARGET_USER" bash -c "
      export http_proxy=\"$PROXY_URL\"
      export https_proxy=\"$PROXY_URL\"
      export all_proxy=\"$SOCKS_URL\"
      yay -S --needed --noconfirm $AUR_PKGS
    "
  else
    echo "  -> Notice: AUR package list is empty."
  fi
else
  echo "  -> Error: pkglist-aur.txt not found."
fi

echo "[9/10] Clone and stow dotfiles..."
su -s /bin/bash "$TARGET_USER" <<EOF
set -e
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export all_proxy="$SOCKS_URL"

# Improved Force Sync Function to kill nested dirs and conflicts
force_sync_repo() {
  local url=\$1
  local path=\$2
  if [ ! -d "\$path" ]; then
    echo "  -> Initializing \$(basename "\$path")..."
    git clone "\$url" "\$path"
  else
    echo "  -> Syncing \$(basename "\$path") (Force Reset to Remote)..."
    cd "\$path"
    git fetch origin main
    git reset --hard origin/main
    git clean -fd
  fi
}

force_sync_repo "$DOTFILES_REPO" "$TARGET_HOME/dot_files"

echo "  -> Executing stow configuration..."
# Keep SSH config owned by dot_files/stow.
SSH_CONFIG_PATH="$TARGET_HOME/.ssh/config"
USER_BACKUP_DIR="$TARGET_HOME/restore_backup_$RESTORE_STAMP"
if [ -e "\$SSH_CONFIG_PATH" ] || [ -L "\$SSH_CONFIG_PATH" ]; then
  backup_target="\$USER_BACKUP_DIR/.ssh/config"
  mkdir -p "\$(dirname "\$backup_target")"
  mv "\$SSH_CONFIG_PATH" "\$backup_target"
  echo "  -> Existing SSH config moved to \$backup_target"
fi

cd "$TARGET_HOME/dot_files" || exit
for target_dir in */; do
  dir_name="\${target_dir%/}"
  if [[ "\$dir_name" =~ ^(\.git|windows_configs)$ ]]; then
    continue
  fi
  stow --restow -t "$TARGET_HOME" "\$dir_name"
done

force_sync_repo "$SCRIPTS_REPO" "$TARGET_HOME/scripts"
EOF

echo "[-] Restore sensitive app configs..."
if [ -n "${SECURE_TAR_TMP:-}" ] && [ -f "$SECURE_TAR_TMP" ]; then
  restore_sensitive_file "$SECURE_TAR_TMP" ".config/rclone/rclone.conf" 600
  restore_sensitive_file "$SECURE_TAR_TMP" ".codex/.env" 600
else
  echo "  -> No decrypted sensitive archive available. Skipping."
fi

echo "[-] Restore Windows WezTerm configuration..."
WIN_PROFILE_CMD=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')

if [ -n "$WIN_PROFILE_CMD" ]; then
  WIN_HOME=$(wslpath "$WIN_PROFILE_CMD")
  WEZTERM_DOTFILES_DIR="$TARGET_HOME/dot_files/windows_configs/wezterm"
  WIN_CONFIG_PARENT="$WIN_HOME/.config"
  WEZTERM_WIN_DIR="$WIN_CONFIG_PARENT/wezterm"

  if [ -d "$WEZTERM_DOTFILES_DIR" ]; then
    sudo -u "$TARGET_USER" bash -c "
      mkdir -p '$WIN_CONFIG_PARENT'
      rm -rf '$WEZTERM_WIN_DIR' 2>/dev/null || true
      cp -r '$WEZTERM_DOTFILES_DIR' '$WEZTERM_WIN_DIR'
    "
    echo "  -> Restored WezTerm config to Windows at $WEZTERM_WIN_DIR as $TARGET_USER."
  else
    echo "  -> Notice: No WezTerm config found in dot_files. Skipping."
  fi
else
  echo "  -> Warning: Failed to resolve Windows User Profile path."
fi

echo "[10/10] Restore default shell configuration..."
SHELL_FILE="$BACKUP_ROOT/data/default_shell.txt"

if [ -f "$SHELL_FILE" ]; then
  TARGET_SHELL=$(cat "$SHELL_FILE" | tr -d '[:space:]')

  if [ -n "$TARGET_SHELL" ] && [ -x "$TARGET_SHELL" ]; then
    if ! grep -Fxq "$TARGET_SHELL" /etc/shells; then
      echo "$TARGET_SHELL" >>/etc/shells
    fi
    chsh -s "$TARGET_SHELL" "$TARGET_USER"
    echo "  -> Default shell successfully changed to $TARGET_SHELL."
  else
    echo "  -> Warning: Executable target shell not found or invalid."
  fi
fi

echo "=== Restore Accomplished ==="
