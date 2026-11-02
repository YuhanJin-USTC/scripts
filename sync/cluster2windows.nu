#!/usr/bin/env nu

# Registered SSH home paths.
let cluster_roots = {
  hfcluster: "/public/home/yuhanjin"
  tycluster: "/work/home/yuhanjin"
  wzcluster: "/work/home/yuhanjin"
}

# Download matching remote directory contents.
def status-label [status: string] {
  match $status {
    "OK" => $"(ansi green)OK(ansi reset)"
    "SKIP" => $"(ansi yellow)SKIP(ansi reset)"
    "ERROR" => $"(ansi red)ERROR(ansi reset)"
    "DRY-RUN" => $"(ansi cyan)DRY-RUN(ansi reset)"
    _ => $status
  }
}

def status [label: string message: string] {
  let text = $"[(status-label $label)] ($message)"
  if $label == "ERROR" {
    print --stderr $text
  } else {
    print $text
  }
}

def check-command [command: string] {
  if ((which $command) | is-empty) {
    status "ERROR" $"Command not found: ($command)."
    exit 1
  }
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
  print $"(ansi cyan)Cluster download(ansi reset)"
  print $"Target: ($remote_src) -> ($dest)"
  print $"Mode: (if $dry_run { 'dry-run' } else { 'run' })"
  print $"Rule: (filter-rule $prefix $suffix)"
  if $dry_run {
    status "DRY-RUN" "No files will be downloaded."
  }
  print ""
}

def main [
  remote: string # SSH host; hf, ty, wz also select the configured cluster aliases
  src_dir: string # Registered clusters: full SSH path or home-relative directory
  dest: path # Local destination (WSL path)
  prefix?: string # File prefix pattern (e.g., "bz")
  suffix?: string # File suffix pattern (e.g., ".sdf")
  --dry-run (-n) # Preview changes without downloading, default
  --run # download for real
] {
  if $run and $dry_run {
    status "ERROR" "Choose only one mode: --dry-run or --run."
    exit 1
  }

  let do_dry_run = not $run
  let dest_path = ($dest | path expand)

  check-command "ssh"
  check-command "rsync"

  let ssh_host = match $remote {
    "hf" => "hfcluster"
    "ty" => "tycluster"
    "wz" => "wzcluster"
    _ => $remote
  }
  let root = ($cluster_roots | get --optional $ssh_host)
  let mapped = if $root != null and not ($src_dir | str starts-with "/") {
    $"($root)/($src_dir)"
  } else { $src_dir }
  # A trailing slash syncs directory contents.
  let src_path = if ($mapped | str ends-with "/") { $mapped } else { $"($mapped)/" }
  let remote_src = $"($ssh_host):($src_path)"

  # Include the requested pattern and exclude everything else.
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
  print $"Input: ($src_dir)"
  print $"Path: (if $root == null { 'unchanged for this SSH host' } else if ($src_dir | str starts-with '/') { 'absolute SSH path' } else { 'relative to the registered SSH home' })"

  if (not $do_dry_run) and not ($dest_path | path exists) {
    mkdir $dest_path
  }

  # Base rsync flags: archive, compress, skip owner/group for WSL/NTFS.
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

  let final_args = ($args | append $rules | append $remote_src | append $dest_path)

  print "Command:"
  print $"  rsync ($final_args | str join ' ')"
  print ""

  # Run rsync or its dry-run preview.
  ^rsync ...$final_args
  let rsync_exit_code = $env.LAST_EXIT_CODE
  if $rsync_exit_code != 0 {
    status "ERROR" $"Cluster download failed with code ($rsync_exit_code)."
    exit $rsync_exit_code
  }

  if $do_dry_run {
    status "OK" "Dry run completed. Add --run to download these files."
  } else {
    status "OK" "Cluster download completed."
  }
}
