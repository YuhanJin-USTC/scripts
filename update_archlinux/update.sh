#!/bin/bash

set -e

MODE="dry-run"

usage() {
  printf '%s\n' \
    "Usage: $0 [--dry-run|--run]" \
    "" \
    "Update Arch Linux packages in WSL." \
    "" \
    "Options:" \
    "  --dry-run   Show available updates and commands only. Default." \
    "  --run       Run real updates." \
    "  -h, --help  Show this help."
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      MODE="dry-run"
      ;;
    --run)
      MODE="run"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: command not found: $cmd"
    exit 1
  fi
}

show_wsl_note() {
  if grep -qi microsoft /proc/version 2>/dev/null; then
    echo ""
    echo "WSL note:"
    echo "  Arch packages are updated here."
    echo "  WSL kernel/runtime is updated from Windows PowerShell:"
    echo "    wsl --update"
  fi
}

show_pacman_updates() {
  echo "[1/2] Official repo updates"
  if command -v checkupdates >/dev/null 2>&1; then
    checkupdates || true
  else
    echo "  checkupdates not found."
    echo "  Install pacman-contrib for safer dry-run checks:"
    echo "    sudo pacman -S --needed pacman-contrib"
    echo "  Fallback local database check:"
    pacman -Qu || true
  fi
}

show_aur_updates() {
  echo ""
  echo "[2/2] AUR updates"
  yay -Qua || true
}

run_updates() {
  if [ "$EUID" -eq 0 ]; then
    echo "Error: do not run this script as root. sudo is used only for pacman."
    exit 1
  fi

  echo "[1/3] Update archlinux-keyring"
  sudo pacman -Sy --needed archlinux-keyring

  echo ""
  echo "[2/3] Update official repo packages"
  sudo pacman -Syu

  echo ""
  echo "[3/3] Update AUR packages"
  yay -Sua
}

need_cmd pacman
need_cmd yay

echo "=== Arch Linux WSL Update ==="

if [ "$MODE" = "dry-run" ]; then
  show_pacman_updates
  show_aur_updates
  echo ""
  echo "Dry run only. To update:"
  echo "  $0 --run"
  echo ""
  echo "Commands that will run:"
  echo "  sudo pacman -Sy --needed archlinux-keyring"
  echo "  sudo pacman -Syu"
  echo "  yay -Sua"
else
  run_updates
  echo ""
  echo "=== Update Accomplished ==="
fi

show_wsl_note
