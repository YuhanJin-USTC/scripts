#!/usr/bin/env nu

# Cluster upload host config.
# Keep login aliases and default roots here so daily commands stay short.
let cluster_hosts = [
  {name: "hfcluster", remote: "hfcluster", remote_root: "/public/home/yuhanjin"}
  {name: "tycluster", remote: "tycluster", remote_root: "/work/home/yuhanjin"}
  {name: "wzcluster", remote: "wzcluster", remote_root: "/work/home/yuhanjin"}
]

let config_base = ($env.CURRENT_FILE | path dirname | path expand)
let rule_cluster_upload = "exclude_rules_cluster_upload"

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

def check-command [cmd: string] {
  if ((which $cmd) | is-empty) {
    status "ERROR" $"Command not found: ($cmd)."
    exit 1
  }
}

def cluster-key [name: string] {
  $name | str lowercase | str replace --all " " "_"
}

def select-cluster [target: string] {
  let key = (cluster-key $target)
  let selected = ($cluster_hosts | where {|item| (cluster-key $item.name) == $key })

  if (($selected | length) == 0) {
    status "ERROR" $"Unknown cluster target: ($target)."
    print "Available targets:"
    for item in $cluster_hosts {
      print $"  ($item.name)"
    }
    exit 1
  }

  $selected | first
}

def assert-source-dir [src: string] {
  if not ($src | path exists) {
    status "ERROR" $"Source directory not found: ($src)."
    exit 1
  }

  if (($src | path type) != "dir") {
    status "ERROR" $"Source is not a directory: ($src)."
    exit 1
  }
}

# Remote path guard.
# Relative paths are placed under the cluster default root; absolute paths are kept.
def assert-safe-remote-dir [remote_dir: string] {
  let clean = ($remote_dir | str trim)

  if ($clean in ["" "/" "." "~"]) {
    status "ERROR" $"Refusing unsafe remote directory: ($remote_dir)."
    exit 1
  }
}

# Remote destination resolver.
# Example: hfcluster + Simulation/a -> /public/home/yuhanjin/Simulation/a
# Example: wzcluster + /work/home/yuhanjin/a -> /work/home/yuhanjin/a
def resolve-remote-dir [cluster: record remote_dir: string] {
  let clean = ($remote_dir | str trim)

  if ($clean | str starts-with "/") {
    $clean
  } else {
    $cluster.remote_root | path join $clean
  }
}

# Rsync directory semantics.
# A trailing slash uploads directory contents instead of nesting the directory itself.
def path-with-trailing-slash [path: string] {
  if ($path | str ends-with "/") {
    $path
  } else {
    $"($path)/"
  }
}

# Run summary shown before any external operation.
def print-header [
  src: string
  remote_dest: string
  remote_root: string
  dry_run: bool
  rule: string
] {
  print ""
  print $"(ansi cyan)Cluster upload(ansi reset)"
  print $"Target: ($src) -> ($remote_dest)"
  print $"Mode: (if $dry_run { 'dry-run' } else { 'run' })"
  print $"Rule: ($rule)"
  print $"Root: ($remote_root)"
  if $dry_run {
    status "DRY-RUN" "No files will be uploaded."
  }
  print ""
}

def main [
  target: string # Cluster target: hfcluster, tycluster, or wzcluster
  src_dir: path # Local source directory
  remote_dir: string # Remote directory, absolute or under the cluster root
  --run # upload for real
  --all-files # upload without the default exclude rule
] {
  let do_dry_run = not $run
  let cluster = (select-cluster $target)
  let src = ($src_dir | path expand)

  # Preflight checks before printing or running remote commands.
  assert-source-dir $src
  assert-safe-remote-dir $remote_dir
  check-command "ssh"
  check-command "rsync"

  # Default upload rule excludes outputs and logs, but keeps source, scripts, and SIF images.
  let rule_file = ($config_base | path join $rule_cluster_upload)
  if (not $all_files) and not ($rule_file | path exists) {
    status "ERROR" $"Cluster upload rule file not found: ($rule_file)"
    exit 1
  }

  # Resolve local and remote transfer endpoints.
  let src_path = (path-with-trailing-slash $src)
  let remote_dir_resolved = (resolve-remote-dir $cluster $remote_dir)
  let remote_path = (path-with-trailing-slash $remote_dir_resolved)
  let remote_dest = $"($cluster.remote):($remote_path)"
  let rule_label = if $all_files { "all files" } else { $rule_file }

  print-header $src_path $remote_dest $cluster.remote_root $do_dry_run $rule_label

  # Remote directory preparation.
  # Dry-run only prints this command; --run executes it before rsync.
  let mkdir_args = [
    $cluster.remote
    "mkdir"
    "-p"
    "--"
    $remote_dir_resolved
  ]

  print "Prepare command:"
  print $"  ssh ($mkdir_args | str join ' ')"
  print ""

  if not $do_dry_run {
    ^ssh ...$mkdir_args
    let ssh_exit_code = $env.LAST_EXIT_CODE
    if $ssh_exit_code != 0 {
      status "ERROR" $"Remote directory preparation failed with code ($ssh_exit_code)."
      exit $ssh_exit_code
    }
  }

  # Base rsync flags.
  # No --delete; --update protects newer remote edits.
  mut args = [
    "-azv",
    "--update",
    "--no-o", "--no-g",
    "--human-readable",
    "--partial",
    "--timeout=600",
    "-e", "ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=10"
  ]

  # Dry-run shows stats only; run mode shows transfer progress.
  if $do_dry_run {
    $args = ($args | append ["--dry-run" "--info=stats2"])
  } else {
    $args = ($args | append "--info=progress2,stats2")
  }

  # Default excludes avoid large output data unless --all-files is requested.
  if not $all_files {
    $args = ($args | append $"--exclude-from=($rule_file)")
  }

  let final_args = ($args | append $src_path | append $remote_dest)

  print "Upload command:"
  print $"  rsync ($final_args | str join ' ')"
  print ""

  # Run rsync or its dry-run preview.
  ^rsync ...$final_args
  let rsync_exit_code = $env.LAST_EXIT_CODE
  if $rsync_exit_code != 0 {
    status "ERROR" $"Cluster upload failed with code ($rsync_exit_code)."
    exit $rsync_exit_code
  }

  if $do_dry_run {
    status "OK" "Dry run completed. Add --run to upload these files."
  } else {
    status "OK" "Cluster upload completed."
  }
}
