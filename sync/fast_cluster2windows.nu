#!/usr/bin/env nu

# Fast-transfer host config.
# Portal paths are separate from SSH home paths.
let cluster_hosts = [
  {name: "hfcluster", address: "hefei03.nscc-hf.cn", port: 65012, user: "yuhanjin", remote_root: "/", ssh_root: "/public/home/yuhanjin"}
  {name: "tycluster", address: "tycs1.hpccube.com", port: 65112, user: "yuhanjin", remote_root: "/", ssh_root: "/work/home/yuhanjin"}
  {name: "wzcluster", address: "wuzh01.hpccube.com", port: 65012, user: "yuhanjin", remote_root: "/", ssh_root: "/work/home/yuhanjin"}
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
def resolve-remote-path [cluster: record remote_path: string portal_path: bool] {
  let clean = $remote_path
  let parts = ($clean | split row "/")
  if (
    ($clean in ["" "." "~"])
    or (($clean | str trim --char "/") == "")
    or ($parts | any {|part| $part in ["." ".."] })
    or ($remote_path =~ '[\x00-\x1f\x7f]')
    or ($clean | str contains '\')
  ) {
    status "ERROR" $"Refusing unsafe remote path: ($remote_path)."
    exit 1
  }

  let mapped = if not $portal_path and ($clean == $cluster.ssh_root or ($clean | str starts-with $"($cluster.ssh_root)/")) {
    $clean | str substring (($cluster.ssh_root | str length)..)
  } else { $clean }
  let portal = if ($mapped | str starts-with "/") { $mapped } else { $"($cluster.remote_root)($mapped)" }
  if ($portal | str trim --char "/") == "" {
    status "ERROR" "The selected SSH home maps to the portal root; choose a directory below it."
    exit 1
  }
  $portal
}

def main [
  target: string # Cluster target: hfcluster, tycluster, wzcluster (hf, ty, wz)
  src: string # Full registered SSH path, home-relative path or absolute portal path
  dest: path # Local destination directory
  prefix?: string # Filename prefix glob
  suffix?: string # Filename suffix glob
  --exclude (-e): string = "" # Reserved; download exclusions need protocol validation
  --dry-run (-n) # Offline preview, default
  --portal-path # Interpret src literally in the portal namespace; bypass SSH-home mapping
  --list # Explicit read-only native list probe; no downloads
  --attributes # Explicit read-only native attributes probe for src; no downloads
  --ssh-list # Explicit recursive SSH metadata selection; no token or downloads
  --run # HF/TY/WZ: SSH metadata, Rayfile payload and verified publication; HF/TY not live-tested
] {
  if ([$dry_run $list $attributes $ssh_list $run] | where {|value| $value } | length) > 1 {
    status "ERROR" "Choose only one mode: --dry-run, --list, --attributes, --ssh-list or --run."
    exit 2
  }
  if $exclude != "" {
    status "ERROR" "Download exclusions require verified listing metadata; use prefix and suffix."
    exit 2
  }
  if ($dest | str trim) == "" {
    status "ERROR" "A local destination directory is required."
    exit 2
  }
  let cluster = (select-cluster $target)
  let clean_src = $src
  let source = (resolve-remote-path $cluster $src $portal_path | str trim --right --char "/")
  let destination = ($dest | path expand --no-symlink)
  let helper = ($env.CURRENT_FILE | path dirname | path join "rayfile_download.py")
  let p = ($prefix | default "")
  let s = ($suffix | default "")
  let args = ["--target" $cluster.name "--source" $source "--destination" $destination $"--prefix=($p)" $"--suffix=($s)"]
  check-command "python3"
  ^python3 -B $helper validate ...$args
  if $env.LAST_EXIT_CODE != 0 { exit $env.LAST_EXIT_CODE }

  let mode = if $run { "run" } else if $list { "list" } else if $attributes { "attributes" } else if $ssh_list { "ssh-list" } else { "dry-run" }
  print ""
  print $"(ansi cyan)Cluster fast download(ansi reset)"
  print $"Target: ($cluster.name):($source) -> ($destination)"
  print $"Mode: ($mode)"
  print $"Rule: (if $p == '' and $s == '' { 'all files' } else { $p + '*' + $s })"
  print $"Input: ($src)"
  print $"Path: (if $portal_path { 'explicit portal namespace' } else if (($clean_src | str starts-with $"($cluster.ssh_root)/") or $clean_src == $cluster.ssh_root) { 'registered SSH home mapped to portal root' } else if ($clean_src | str starts-with '/') { 'absolute portal path' } else { 'relative to portal home' })"
  print "Planned layout: preserve existing files; incoming name.1.ext on collision; inner paths retained"
  if $mode == "dry-run" {
    status "DRY-RUN" "Offline plan only; no token, client, server access or destination creation."
    print "Metadata: --ssh-list explicitly reads the mapped SSH source; --list and --attributes show raw native diagnostics."
    print "Protocol: hf/ty/wz --run share SSH metadata and Rayfile batches; only WZ has live fixture acceptance."
    return
  }
  if $mode in ["list" "attributes"] {
    print "Probe: raw native response for this source only; filters and local destination are not used."
  }
  if $mode == "run" {
    print "Transfer: SSH metadata before and after; Rayfile payload; complete verification before publication."
  }
  ^python3 -B $helper $mode ...$args
  let code = $env.LAST_EXIT_CODE
  if $code != 0 { exit $code }
}
