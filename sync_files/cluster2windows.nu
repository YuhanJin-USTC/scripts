#!/usr/bin/env nu

# Syncs specific files from a remote directory directly to a local destination (flat structure).
# Logic: remote:src_dir/prefix*suffix -> local/prefix*suffix
def status-label [status: string] {
  match $status {
    "OK" => $"(ansi green)OK(ansi reset)"
    "ERROR" => $"(ansi red)ERROR(ansi reset)"
    "DRY-RUN" => $"(ansi cyan)DRY-RUN(ansi reset)"
    _ => $status
  }
}

def status [label: string message: string] {
  print $"[(status-label $label)] ($message)"
}

def filter-rule [prefix: string suffix: string] {
  if ($prefix == "" and $suffix == "") {
    "all files"
  } else {
    $"($prefix)*($suffix)"
  }
}

def print-header [
  remote_src: string
  dest: path
  prefix: string
  suffix: string
  dry_run: bool
] {
  print ""
  print $"(ansi cyan)Cluster transfer(ansi reset)"
  print $"Target: ($remote_src) -> ($dest)"
  print $"Mode: (if $dry_run { 'dry-run' } else { 'run' })"
  print $"Rule: (filter-rule $prefix $suffix)"
  if $dry_run {
    status "DRY-RUN" "No files will be downloaded."
  }
  print ""
}

def main [
  remote: string # SSH host (e.g., "user@server")
  src_dir: string # Remote source directory
  dest: path # Local destination (WSL path)
  prefix?: string # File prefix pattern (e.g., "bz")
  suffix?: string # File suffix pattern (e.g., ".sdf")
  --dry-run (-n) # Preview changes without downloading, default
  --run # download for real
] {
  let do_dry_run = not $run
  let dest_path = ($dest | path expand)

  # Ensure remote path ends with '/' to sync contents, not the directory itself
  let src_path = if ($src_dir | str ends-with "/") { $src_dir } else { $"($src_dir)/" }
  let remote_src = $"($remote):($src_path)"

  # Build rsync filter rules dynamically
  # 1. Include the specific files (prefix*suffix)
  # 2. Exclude everything else
  let p = ($prefix | default "")
  let s = ($suffix | default "")

  let rules = if ($p == "" and $s == "") {
    []
  } else {
    [
      $"--include=($p)*($s)"
      "--exclude=*"
    ]
  }

  print-header $remote_src $dest_path $p $s $do_dry_run

  if (not $do_dry_run) and not ($dest_path | path exists) {
    mkdir $dest_path
  }

  # Base flags: archive, compress, skip owner/group (for WSL/NTFS)
  mut args = [
    "-amz", "-v",
    "--no-o", "--no-g", "--no-perms", "--no-times", "--size-only",
    "--partial",
    "--timeout=600",
    "-e", "ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=10"
  ]

  if $do_dry_run {
    $args = ($args | append ["--dry-run"])
  }

  # Construct final command arguments
  let final_args = ($args | append $rules | append $remote_src | append $dest_path)

  print "Command:"
  print $"  rsync ($final_args | str join ' ')"
  print ""

  # Execute rsync
  try {
    ^rsync ...$final_args
    if $do_dry_run {
      status "OK" "Dry run completed. Add --run to download these files."
    } else {
      status "OK" "Cluster transfer completed."
    }
  } catch {
    status "ERROR" "Cluster transfer failed."
    exit 1
  }
}
