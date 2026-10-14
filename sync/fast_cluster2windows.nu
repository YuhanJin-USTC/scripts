#!/usr/bin/env nu

# Fast-transfer host config.
# Portal paths are separate from SSH home paths.
let cluster_hosts = [
  {name: "hfcluster", address: "hefei03.nscc-hf.cn", port: 65012, user: "yuhanjin", remote_root: "/"}
  {name: "tycluster", address: "tycs1.hpccube.com", port: 65112, user: "yuhanjin", remote_root: "/"}
  {name: "wzcluster", address: "wuzh01.hpccube.com", port: 65012, user: "yuhanjin", remote_root: "/"}
]

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

def print-header [
  remote_src: string
  dest: path
  dry_run: bool
  rule: string
] {
  print ""
  print $"(ansi cyan)Cluster fast download(ansi reset)"
  print $"Target: ($remote_src) -> ($dest)"
  print $"Mode: (if $dry_run { 'dry-run' } else { 'run' })"
  print $"Rule: ($rule)"
  print "Existing: rename"
  if $dry_run {
    status "DRY-RUN" "No files will be downloaded."
  }
  print ""
}

def main [
  target: string # Cluster target: hfcluster, tycluster, or wzcluster (hf, ty, wz)
  src: string # Remote file or directory, using the portal path
  dest: path # Local destination directory (WSL path)
  --exclude (-e): string = "" # Additional wildcard excludes, separated by semicolons
  --dry-run (-n) # Preview the command without connecting, default
  --run # download for real
] {
  if $run and $dry_run {
    status "ERROR" "Choose only one mode: --dry-run or --run."
    exit 1
  }

  if ($dest | str trim) == "" {
    status "ERROR" "A local destination directory is required."
    exit 1
  }

  let do_dry_run = not $run
  let cluster = (select-cluster $target)
  let src_path = (resolve-remote-path $cluster $src)
  let dest_path = ($dest | path expand)
  let custom_rules = if $exclude == "" { [] } else { $exclude | split row ";" | str trim }
  let patterns = (exclude-patterns $custom_rules)

  if ($dest_path | path exists) and (($dest_path | path type) != "dir") {
    status "ERROR" $"Destination is not a directory: ($dest_path)."
    exit 1
  }
  if $dest_path == "/" {
    status "ERROR" "Refusing the local root as a destination."
    exit 1
  }
  check-command "rayfile-c"

  let remote_src = $"($cluster.name):($src_path)"
  let rule_label = if ($patterns | is-empty) { "all files" } else { $"exclude: ($patterns | str join ';')" }
  print-header $remote_src $dest_path $do_dry_run $rule_label

  # Keep the portal source path unchanged; rsync slash rules do not apply.
  mut args = [
    "-a", $cluster.address,
    "-P", ($cluster.port | into string),
    "-u", $cluster.user,
    "-no-meta",
    "-symbolic-links", "follow",
    "-retry", "10", "-retrytimeout", "30",
    "-o", "download", "-s", $src_path, "-d", $dest_path,
    "-file-update", "rename"
  ]

  # Repeated -exd options replace earlier rules.
  if not ($patterns | is-empty) {
    $args = ($args | append ["-exd" ($patterns | str join ";")])
  }

  print "Command:"
  print $"  rayfile-c (command-text ($args | append ['-w' '<hidden>']))"
  print ""

  # The client has no native dry-run mode.
  if $do_dry_run {
    status "OK" "Dry run completed. Add --run to download these files."
    return
  }

  let token = (transfer-token)
  if not ($dest_path | path exists) {
    mkdir $dest_path
  }

  let final_args = ($args | append ["-w" $token])
  # Keep native progress and report external failures.
  let rayfile_exit_code = try {
    ^rayfile-c ...$final_args
    $env.LAST_EXIT_CODE
  } catch {|err|
    $err.exit_code? | default 1
  }
  if $rayfile_exit_code != 0 {
    status "ERROR" $"Cluster fast download failed with code ($rayfile_exit_code)."
    exit $rayfile_exit_code
  }

  status "OK" "Cluster fast download completed."
}
