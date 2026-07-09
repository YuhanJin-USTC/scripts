#!/bin/bash

set -e

MODE="dry-run"

color() {
  printf '\033[%sm%s\033[0m' "$1" "$2"
}

status_label() {
  case "$1" in
    OK)
      color 32 OK
      ;;
    SKIP)
      color 33 SKIP
      ;;
    ERROR)
      color 31 ERROR
      ;;
    DRY-RUN)
      color 36 DRY-RUN
      ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

status() {
  printf '[%s] %s\n' "$(status_label "$1")" "$2"
}

print_header() {
  echo ""
  color 36 "Arch update"
  echo ""
  echo "Target: Arch Linux WSL"
  echo "Mode: $MODE"
  echo "Rule: official repo + AUR"
  if [ "$MODE" = "dry-run" ]; then
    status DRY-RUN "No packages will be changed."
  fi
  echo ""
}

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

# Parse mode before checking package tools.
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
      status ERROR "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

# Require local package tools before preview or update.
need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    status ERROR "Command not found: $cmd"
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

# Show official repo updates without changing packages.
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

# Run the real update sequence.
run_updates() {
  if [ "$EUID" -eq 0 ]; then
    status ERROR "Do not run this script as root. sudo is used only for pacman."
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

print_header

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
  status OK "Dry run completed. Add --run to update packages."
else
  run_updates
  echo ""
  status OK "Update complete."
fi

show_wsl_note
