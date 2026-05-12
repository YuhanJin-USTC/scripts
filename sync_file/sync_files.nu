#!/usr/bin/env nu

# src & dest path config
let terminal_path_win = "/mnt/d"
let terminal_path_linux = "/home/yuhanjin"
let NAS_home_path = "/mnt/y"
let NAS_group_path = "/mnt/z/金虞焓"
let webdav_remote = "ustcpan"
let config_base = "/home/yuhanjin/scripts/sync_file/"

# rule file
let rule_win2nas = "exclude_rules_windows_nas_home"
let rule_wsl2nas = "exclude_rules_linux_nas_home"
let rule_nas_home2nas_group = "exclude_rules_nas_home_nas_group"

# log file
let log_file = ($env.HOME | path join ".cache/sync_files.log")

# log function
def log [message: string] {
  let timestamp = (date now | format date '%Y-%m-%d %H:%M:%S')
  let log_entry = $"($timestamp): ($message)"
  print $log_entry
  $log_entry | save --append $log_file
}

# check whether path exists
def check-path [path: string name: string] {
  if not ($path | path exists) {
    log $"ERROR: Path for ($name) not found: ($path). Aborting."
    exit 1
  }
}

# sync function
def run-rsync [
  src: string
  dest: string
  rule_file: string
  description: string
  --delete # whether use delete arg
] {
  log $"Starting sync: ($description)..."

  # rsync args
  mut args = [-arv]
  if $delete { $args = ($args | append "--delete") }
  $args = ($args | append $"--exclude-from=($rule_file)")
  $args = ($args | append "--no-links")
  $args = ($args | append $"($src)/")
  $args = ($args | append $"($dest)/")

  # run
  let final_args = $args
  do { ^rsync ...$final_args }

  let exit_code = $env.LAST_EXIT_CODE
  if $exit_code == 0 {
    log $"SUCCESS: ($description)"
  } else {
    log $"ERROR: ($description) failed with code ($exit_code)"
  }
}

# main function
log "=== Starting file synchronization process ==="

# 1. check whether path exists 
check-path $NAS_home_path "NAS Home Mount"
check-path $NAS_group_path "NAS Group Mount"
check-path $terminal_path_win "Windows Mount"

check-path ($config_base | path join $rule_win2nas) "rule file for Windows to NAS"
check-path ($config_base | path join $rule_wsl2nas) "rule file for WSL to NAS"
check-path ($config_base | path join $rule_nas_home2nas_group) "rule file for NAS home to NAS group"

# 2. Windows -> NAS Home
run-rsync $terminal_path_win $NAS_home_path ($config_base | path join $rule_win2nas) "Windows to NAS Home"

# 3. Linux -> NAS Home
run-rsync $terminal_path_linux $NAS_home_path ($config_base | path join $rule_wsl2nas) "Linux to NAS Home"

# 4. NAS Home -> NAS Group
run-rsync $NAS_home_path $NAS_group_path ($config_base | path join $rule_nas_home2nas_group) "NAS Home to NAS Group" --delete

# 5. NAS Home -> WebDAV
log $"Starting sync from ($NAS_home_path) to ustcpan"

do { ^rclone copy -v --progress --transfers 4 --retries 3 --size-only --exclude="#recycle/**" $"($NAS_home_path)/" $"($webdav_remote):NAS_HOME" }

if $env.LAST_EXIT_CODE == 0 {
  log "SUCCESS: sync from nas home to webdav"
} else {
  log $"ERROR: sync from nas home to webdav failed with code ($env.LAST_EXIT_CODE)"
}

log "=== All sync operations completed successfully ==="
