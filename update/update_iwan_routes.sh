#!/usr/bin/env bash
set -e

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script_path=$(wslpath -w "$script_dir/update_iwan_routes.ps1")

exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script_path" "$@"
