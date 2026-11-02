#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="$HOME/Tool_Project/Figure_Browser"

usage() {
  printf '%s\n' \
    "Usage: run_matlab_browser [--open] [--no-open]" \
    "" \
    "Open the existing MATLAB Figure Browser build from any directory." \
    "" \
    "Options:" \
    "  --open      Open the browser (default)." \
    "  --no-open   Suppress browser launch; takes precedence over --open." \
    "  -h, --help  Show this help." \
    "" \
    "Keep the terminal open for a new instance; press Ctrl-C to stop it." \
    "A compatible existing instance is reused and this command exits." \
    "" \
    "Examples:" \
    "  run_matlab_browser" \
    "  run_matlab_browser --no-open"
}

show_help=0
for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help=1 ;;
    --open|--no-open) ;;
    *)
      printf '[ERROR] Unknown option: %s\n' "$arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$show_help" == 1 ]]; then
  usage
  exit 0
fi

if [[ ! -f "$APP_DIR/start.sh" ]]; then
  printf '[ERROR] Launcher not found: %s\n' "$APP_DIR/start.sh" >&2
  exit 1
fi

exec bash "$APP_DIR/start.sh" --open "$@"
