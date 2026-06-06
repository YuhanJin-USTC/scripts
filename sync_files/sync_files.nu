#!/usr/bin/env nu

# src & dest path config
let nas_home_path = "/mnt/y"
let nas_group_path = "/mnt/z/金虞焓"
let matlab_postprocess_path = "/mnt/d/Document/Matlab"
let nas_matlab_postprocess_path = "/mnt/z/金虞焓/Post_Process"
let under_graduate_path = "/mnt/c/Users/17865/Desktop/Under Graduate"
let config_base = "/home/yuhanjin/scripts/sync_file"

# rule file
let rule_nas_only = "exclude_rules_nas_only"

# log file
let log_file = ($env.HOME | path join ".cache/sync_files.log")

# sync list
let sync_items = [
  {
    src: "/home/yuhanjin/dot_files"
    dest_root: $nas_home_path
    dest_name: "dot_files"
    description: "dot_files to NAS Home"
  }
  {
    src: "/home/yuhanjin/scripts"
    dest_root: $nas_home_path
    dest_name: "scripts"
    description: "scripts to NAS Home"
  }
  {
    src: "/home/yuhanjin/Code_Program"
    dest_root: $nas_group_path
    dest_name: "Code_Program"
    description: "Code_Program to NAS Group"
  }
  {
    src: "/home/yuhanjin/Simulation"
    dest_root: $nas_group_path
    dest_name: "Simulation"
    description: "Simulation to NAS Group"
  }
  {
    src: "/home/yuhanjin/Source_Code"
    dest_root: $nas_group_path
    dest_name: "Source_Code"
    description: "Source_Code to NAS Group"
  }
  {
    src: $under_graduate_path
    dest_root: $nas_home_path
    dest_name: "Under_Graduate"
    description: "Under Graduate to NAS Home"
  }
  {
    src: $matlab_postprocess_path
    dest_root: $nas_matlab_postprocess_path
    dest_name: "Matlab"
    description: "Matlab postprocess data to NAS Group"
  }
]

# log function
def write-log [message: string] {
  let timestamp = (date now | format date '%Y-%m-%d %H:%M:%S')
  let log_entry = $"($timestamp): ($message)"
  $"($log_entry)\n" | save --append $log_file
}

def info [message: string] {
  print $message
  write-log $message
}

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
  print $"[(status-label $label)] ($message)"
  write-log $"[($label)] ($message)"
}

# check whether path exists
def check-path [path: string name: string] {
  if not ($path | path exists) {
    status "ERROR" $"Path for ($name) not found: ($path). Aborting."
    exit 1
  }
}

def target-path [src: string dest_root: string dest_name: string] {
  let name = if $dest_name == "" { $src | path basename } else { $dest_name }
  $dest_root | path join $name
}

def print-header [target: string dry_run: bool rule_file: string] {
  print ""
  print $"(ansi cyan)NAS sync(ansi reset)"
  info $"Target: ($target)"
  info $"Mode: (if $dry_run { 'dry-run' } else { 'run' })"
  info $"Rule: ($rule_file)"
  if $dry_run {
    status "DRY-RUN" "No files will be changed."
  }
  print ""
}

def print-plan [items: list rule_file: string] {
  info $"Sync items: ($items | length)"
  for row in ($items | enumerate) {
    let item = $row.item
    let src = ($item.src | str trim)
    let index = ($row.index + 1)
    let dest = if $src == "" {
      "(skip: empty source)"
    } else {
      target-path $src $item.dest_root $item.dest_name
    }
    info $"  [($index)/($items | length)] ($item.description)"
    info $"      Source: (if $src == '' { '(empty)' } else { $src })"
    info $"      Destination: ($dest)"
  }
  info $"Exclude: ($rule_file)"
  print ""
}

def sync-key [name: string] {
  $name | str downcase | str replace --all " " "_"
}

def item-names [item: record] {
  [
    $item.dest_name
    ($item.src | path basename)
  ] | each { |name| sync-key $name } | uniq
}

def select-items [items: list target: string] {
  let key = (sync-key $target)
  if $key == "all" {
    return $items
  }

  let selected = ($items | where { |item| $key in (item-names $item) })
  if ($selected | length) == 0 {
    status "ERROR" $"Unknown sync target: ($target)"
    info "Available targets:"
    for item in $items {
      info $"  ($item.dest_name)"
    }
    info "  all"
    exit 1
  }

  $selected
}

def check-dest-roots [items: list] {
  for root in ($items | get dest_root | uniq) {
    check-path $root $"Destination root ($root)"
  }
}

# sync function
def run-rsync [
  item: record
  index: int
  total: int
  rule_file: string
  dry_run: bool
] {
  let src = ($item.src | str trim)

  if $src == "" {
    status "SKIP" $"[($index)/($total)] ($item.description): source path is empty."
    return
  }

  if not ($src | path exists) {
    status "ERROR" $"[($index)/($total)] ($item.description): source path not found: ($src). Aborting."
    exit 1
  }

  let dest = (target-path $src $item.dest_root $item.dest_name)
  print $"(ansi blue)----------------------------------------(ansi reset)"
  info $"[($index)/($total)] ($item.description)"
  info $"SRC: ($src)"
  info $"DST: ($dest)"

  mut args = ["-a" "--update" "--no-links" "--human-readable"]
  if $dry_run {
    $args = ($args | append "--dry-run")
    $args = ($args | append "--info=stats2")
  } else {
    $args = ($args | append "--info=progress2,stats2")
  }
  $args = ($args | append $"--exclude-from=($rule_file)")
  $args = ($args | append $"($src)/")
  $args = ($args | append $"($dest)/")

  let final_args = $args
  do { ^rsync ...$final_args }

  let exit_code = $env.LAST_EXIT_CODE
  if $exit_code == 0 {
    status "OK" $"[($index)/($total)] ($item.description)"
  } else {
    status "ERROR" $"[($index)/($total)] ($item.description) failed with code ($exit_code)"
    exit $exit_code
  }
}

def main [
  target: string = "all" # sync target folder, or all
  --run # sync for real
] {
  let do_dry_run = not $run

  let rule_file = ($config_base | path join $rule_nas_only)
  check-path $rule_file "NAS-only rule file"

  let selected_items = (select-items $sync_items $target)
  check-dest-roots $selected_items

  print-header $target $do_dry_run $rule_file
  write-log "=== Starting NAS synchronization process ==="
  if $do_dry_run { write-log "DRY RUN: no files will be changed." }
  write-log $"Target: ($target)"
  print-plan $selected_items $rule_file

  let total = ($selected_items | length)
  for row in ($selected_items | enumerate) {
    run-rsync $row.item ($row.index + 1) $total $rule_file $do_dry_run
  }

  print $"(ansi blue)----------------------------------------(ansi reset)"
  if $do_dry_run {
    status "OK" "Dry run completed. Add --run to sync these paths."
  } else {
    status "OK" "NAS synchronization completed."
  }
  write-log "=== NAS synchronization completed ==="
}
