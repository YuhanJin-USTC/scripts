#!/bin/bash

set -e

MODE="dry-run"
MODE_SEEN=0
SCOPE="all"
SCOPE_SEEN=0
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NVIM_HELPER="$SCRIPT_DIR/../backup/archlinux/nvim_state.py"

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
  local label="$1"
  local message="$2"
  if [ "$label" = "ERROR" ]; then
    printf '[%s] %s\n' "$(status_label "$label")" "$message" >&2
  else
    printf '[%s] %s\n' "$(status_label "$label")" "$message"
  fi
}

print_header() {
  echo ""
  color 36 "Arch update"
  echo ""
  echo "Target: Arch Linux WSL"
  echo "Mode: $MODE"
  echo "Rule: full system upgrade, then isolated Neovim candidate"
  echo "Scope: $SCOPE"
  if [ "$MODE" = "dry-run" ]; then
    status DRY-RUN "No packages, editor files, or active generation will be changed."
  fi
  echo ""
}

usage() {
  printf '%s\n' \
    "Usage: $0 [--dry-run|--run] [--system-only|--editor-only]" \
    "" \
    "Preview or update Arch Linux and prepare a managed Neovim generation." \
    "" \
    "Options:" \
    "  --dry-run   Show available updates and commands only. Default." \
    "  --run       Run selected updates; editor activation is a separate command." \
    "  --system-only  Update Arch packages only." \
    "  --editor-only  Prepare Neovim only; do not change packages." \
    "  -h, --help  Show this help." \
    "" \
    "Examples:" \
    "  $0" \
    "  $0 --run"
}

# Parse mode before checking package tools.
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      if [ "$MODE_SEEN" -eq 1 ]; then
        status ERROR "Choose only one mode: --dry-run or --run."
        exit 1
      fi
      MODE="dry-run"
      MODE_SEEN=1
      ;;
    --run)
      if [ "$MODE_SEEN" -eq 1 ]; then
        status ERROR "Choose only one mode: --dry-run or --run."
        exit 1
      fi
      MODE="run"
      MODE_SEEN=1
      ;;
    --system-only | --editor-only)
      if [ "$SCOPE_SEEN" -eq 1 ]; then
        status ERROR "Choose only one scope: --system-only or --editor-only."
        exit 1
      fi
      SCOPE="${1#--}"
      SCOPE_SEEN=1
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      status ERROR "Unknown option: $1."
      usage >&2
      exit 1
      ;;
  esac
  shift
done

# Require local package tools before preview or update.
need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    status ERROR "Command not found: $cmd."
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
    if checkupdates; then
      :
    else
      local result=$?
      if [ "$result" -ne 2 ]; then
        status ERROR "Official update query failed ($result)."
        return "$result"
      fi
      status SKIP "No official updates."
    fi
  else
    echo "  checkupdates not found."
    echo "  Install pacman-contrib for safer dry-run checks:"
    echo "    sudo pacman -S --needed pacman-contrib"
    echo "  Fallback local database check:"
    pacman -Qu
  fi
}

show_aur_updates() {
  echo ""
  echo "[2/2] AUR updates"
  yay -Qua
}

run_package_command() {
  local log_file command_status
  local -a pipeline_status
  if ! log_file=$(mktemp "${TMPDIR:-/tmp}/arch-update.XXXXXXXX.log"); then
    status ERROR "Could not create the package transaction log."
    return 1
  fi
  if "$@" 2>&1 | tee "$log_file"; then
    pipeline_status=("${PIPESTATUS[@]}")
  else
    pipeline_status=("${PIPESTATUS[@]}")
  fi
  command_status=${pipeline_status[0]}
  if [ "${pipeline_status[1]}" -ne 0 ]; then
    status ERROR "Package log capture failed. Inspect $log_file before continuing."
    return 1
  fi
  if [ "$command_status" -ne 0 ]; then
    status ERROR "Package command failed ($command_status). Log: $log_file"
    return "$command_status"
  fi
  if sed -E 's/\x1B\[[0-9;]*[mK]//g' "$log_file" | grep -Eq '^error: (command failed to execute correctly|failed to commit transaction|failed to synchronize all databases)'; then
    status ERROR "Pacman reported a failed transaction or ALPM hook despite exit 0. Installed packages remain; inspect $log_file."
    return 1
  fi
  CODEX_TEMP_CLEANUP=1 rm -- "$log_file"
}

# Run the real update sequence.
run_updates() {
  if [ "$EUID" -eq 0 ]; then
    status ERROR "Do not run this script as root. sudo is used only for pacman."
    exit 1
  fi

  echo "[1/2] Upgrading official packages, including archlinux-keyring."
  if ! run_package_command sudo pacman -Syu --needed archlinux-keyring; then
    status ERROR "System phase failed during the full official upgrade."
    return 1
  fi

  echo ""
  echo "[2/2] Updating AUR packages."
  if ! run_package_command yay -Sua; then
    status ERROR "System phase failed during the AUR upgrade."
    return 1
  fi
}

run_editor() {
  need_cmd python3
  local result generation identity
  if [ "$MODE" = "dry-run" ]; then
    python3 -B "$NVIM_HELPER" --home "$HOME" status --json || return $?
    python3 -B "$NVIM_HELPER" --home "$HOME" prepare --json || return $?
    return
  fi
  if ! result=$(python3 -B "$NVIM_HELPER" --home "$HOME" prepare --run --json); then
    status ERROR "Editor preparation failed. Active Neovim was not switched; candidate diagnostics are retained."
    return 1
  fi
  generation=$(python3 -B -c 'import json,sys; print(json.load(sys.stdin)["generation"])' <<< "$result") || return $?
  identity=$(python3 -B -c 'import json,sys; print(json.load(sys.stdin)["identity"])' <<< "$result") || return $?
  printf '%s\n' "$result"
  status OK "Editor candidate validated: $generation."
  echo "Review this generation, then explicitly activate it:"
  printf '  python3 -B %q --home %q activate %q --expect-identity %q --run --json\n' "$NVIM_HELPER" "$HOME" "$generation" "$identity"
}

print_header
if [ "$MODE" = "run" ] && [ "$EUID" -eq 0 ]; then
  status ERROR "Do not run this script as root. sudo is used only for pacman."
  exit 1
fi

if [ "$SCOPE" != "editor-only" ]; then
  need_cmd pacman
  need_cmd yay
  if [ "$MODE" = "dry-run" ]; then
    show_pacman_updates
    show_aur_updates
    echo "Commands that will run:"
    echo "  sudo pacman -Syu --needed archlinux-keyring"
    echo "  yay -Sua"
  else
    if ! run_updates; then
      status ERROR "System update failed; editor preparation was not started."
      exit 1
    fi
    status OK "System upgrade completed; system packages are not rolled back on later editor failure."
  fi
  show_wsl_note
fi

if [ "$SCOPE" != "system-only" ]; then
  if ! run_editor; then
    status ERROR "Editor phase did not complete. Earlier system updates remain in place."
    exit 1
  fi
fi
if [ "$MODE" = "dry-run" ]; then
  status OK "Preview completed. Add --run for the selected scope."
else
  status OK "Selected update phases completed. Editor activation remains explicit."
fi
