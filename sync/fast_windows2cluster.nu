#!/usr/bin/env nu

# Fast-transfer host config.
# Portal paths are separate from SSH home paths.
let cluster_hosts = [
  {name: "hfcluster", address: "hefei03.nscc-hf.cn", port: 65012, user: "yuhanjin", remote_root: "/"}
  {name: "tycluster", address: "tycs1.hpccube.com", port: 65112, user: "yuhanjin", remote_root: "/"}
  {name: "wzcluster", address: "wuzh01.hpccube.com", port: 65012, user: "yuhanjin", remote_root: "/"}
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
  let key = ($name | str lowercase | str replace --all " " "_")
  match $key {
    "hf" => "hfcluster"
    "ty" => "tycluster"
    "wz" => "wzcluster"
    _ => $key
  }
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

# Reject root targets and parent traversal.
def resolve-remote-path [cluster: record remote_path: string] {
  let clean = ($remote_path | str trim)
  let parts = ($clean | split row "/")
  if (
    ($clean in ["" "." "~"])
    or (($clean | str trim --char "/") == "")
    or ($parts | any {|part| $part in ["." ".."] })
    or ($clean =~ '[\r\n\x00-\x1f]')
    or ($clean | str contains '\')
  ) {
    status "ERROR" $"Refusing unsafe remote path: ($remote_path)."
    exit 1
  }

  if ($clean | str starts-with "/") {
    $clean
  } else {
    $"($cluster.remote_root)($clean)"
  }
}

def exclude-patterns [rules: list<string>] {
  mut patterns = []
  for rule in $rules {
    if (
      ($rule | str trim) == ""
      or ($rule =~ '[;\r\n\x00-\x1f]')
      or ($rule | str starts-with "!")
      or ($rule | str starts-with "-")
      or ($rule | str starts-with "+")
    ) {
      status "ERROR" $"Unsupported exclude pattern: ($rule)."
      exit 1
    }

    # Directory rules also match descendants.
    if ($rule | str ends-with "/") {
      let directory = ($rule | str trim --right --char "/")
      if $directory == "" {
        status "ERROR" "Refusing an empty directory exclude."
        exit 1
      }
      $patterns = ($patterns | append [$directory $"*/($directory)" $"*/($directory)/*"])
    } else {
      $patterns = ($patterns | append $rule)
    }
  }
  $patterns | uniq
}

def command-text [args: list<string>] {
  $args | each {|arg|
    if ($arg =~ '^[a-zA-Z0-9_./:@=+-]+$') {
      $arg
    } else {
      $arg | to nuon
    }
  } | str join " "
}

# Read credentials only for real transfers.
def transfer-token [] {
  let preset = ($env.RAYFILE_TOKEN? | default "")
  let token = if $preset != "" {
    $preset
  } else {
    if not (is-terminal --stdin) {
      status "ERROR" "Set RAYFILE_TOKEN for a non-interactive transfer."
      exit 1
    }
    input --suppress-output "Fast-transfer token: "
  }
  if ($token | str trim) == "" or ($token =~ '[\r\n\x00]') {
    status "ERROR" "A non-empty, single-line fast-transfer token is required."
    exit 1
  }
  $token
}

def assert-source [src: string] {
  if not ($src | path exists) {
    status "ERROR" $"Source not found: ($src)."
    exit 1
  }
  if (($src | path type) not-in ["dir" "file"]) {
    status "ERROR" $"Source is not a file or directory: ($src)."
    exit 1
  }
  if $src == "/" {
    status "ERROR" "Refusing the local root as a source."
    exit 1
  }
}

def print-header [
  src: string
  remote_dest: string
  remote_root: string
  dry_run: bool
  rule: string
] {
  print ""
  print $"(ansi cyan)Cluster fast upload(ansi reset)"
  print $"Target: ($src) -> ($remote_dest)"
  print $"Mode: (if $dry_run { 'dry-run' } else { 'run' })"
  print $"Rule: ($rule)"
  print $"Root: ($remote_root)"
  print "Existing: rename"
  if $dry_run {
    status "DRY-RUN" "No files will be uploaded."
  }
  print ""
}

def main [
  target: string # Cluster target: hfcluster, tycluster, or wzcluster (hf, ty, wz)
  src: path # Local source file or directory
  remote_dir: string # Remote destination directory, using the portal path
  --exclude (-e): string = "" # Additional wildcard excludes, separated by semicolons
  --dry-run (-n) # Preview the command without connecting, default
  --run # upload for real
  --all-files # upload without the default exclude rule
] {
  if $run and $dry_run {
    status "ERROR" "Choose only one mode: --dry-run or --run."
    exit 1
  }

  if ($src | str trim) == "" {
    status "ERROR" "A local source file or directory is required."
    exit 1
  }

  let do_dry_run = not $run
  let cluster = (select-cluster $target)
  let src_path = ($src | path expand)
  let remote_path = (resolve-remote-path $cluster $remote_dir)

  # Preflight checks before printing or running remote commands.
  assert-source $src_path
  check-command "rayfile-c"

  let rule_file = ($config_base | path join $rule_cluster_upload)
  if (not $all_files) and not ($rule_file | path exists) {
    status "ERROR" $"Cluster upload rule file not found: ($rule_file)"
    exit 1
  }

  # Reuse the upload rules; only --all-files bypasses them.
  let default_rules = if $all_files {
    []
  } else {
    open --raw $rule_file | lines | str trim | where {|line| $line != "" and not ($line | str starts-with "#") }
  }
  let custom_rules = if $exclude == "" { [] } else { $exclude | split row ";" | str trim }
  let patterns = (exclude-patterns ($default_rules | append $custom_rules))
  let rule_label = if not $all_files {
    if $exclude == "" { $rule_file } else { $"($rule_file) + custom excludes" }
  } else if ($patterns | is-empty) {
    "all files"
  } else {
    $"exclude: ($patterns | str join ';')"
  }
  let remote_dest = $"($cluster.name):($remote_path)"
  print-header $src_path $remote_dest $cluster.remote_root $do_dry_run $rule_label

  # Use the portal destination; no SSH preparation or root translation.
  mut args = [
    "-a", $cluster.address,
    "-P", ($cluster.port | into string),
    "-u", $cluster.user,
    "-no-meta",
    "-symbolic-links", "follow",
    "-retry", "10", "-retrytimeout", "30",
    "-o", "upload", "-s", $src_path, "-d", $remote_path,
    "-file-update", "rename"
  ]

  # Repeated -exd options replace earlier rules.
  if not ($patterns | is-empty) {
    $args = ($args | append ["-exd" ($patterns | str join ";")])
  }

  print "Upload command:"
  print $"  rayfile-c (command-text ($args | append ['-w' '<hidden>']))"
  print ""

  # The client has no native dry-run mode.
  if $do_dry_run {
    status "OK" "Dry run completed. Add --run to upload these files."
    return
  }

  let token = (transfer-token)
  let final_args = ($args | append ["-w" $token])
  # Keep native progress and report external failures.
  let rayfile_exit_code = try {
    ^rayfile-c ...$final_args
    $env.LAST_EXIT_CODE
  } catch {|err|
    $err.exit_code? | default 1
  }
  if $rayfile_exit_code != 0 {
    status "ERROR" $"Cluster fast upload failed with code ($rayfile_exit_code)."
    exit $rayfile_exit_code
  }

  status "OK" "Cluster fast upload completed."
}
