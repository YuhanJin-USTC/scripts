#!/usr/bin/env nu

# Copy latest downloaded cluster SSH keys to WSL and Windows targets.
def status-label [label: string] {
  match $label {
    "OK" => $"(ansi green)OK(ansi reset)"
    "SKIP" => $"(ansi yellow)SKIP(ansi reset)"
    "ERROR" => $"(ansi red)ERROR(ansi reset)"
    _ => $label
  }
}

def status [label: string message: string] {
  print $"[(status-label $label)] ($message)"
}

def field [name: string value: string] {
  print $"($name): ($value)"
}

def main [] {
  let src_dir = ("/mnt/d/Download/Edge" | path expand)
  let win_ssh_dest = "/mnt/c/Users/17865/.ssh"
  let wsl_ssh_dest = ("~/.ssh" | path expand)

  print ""
  print $"(ansi cyan)Cluster SSH key sync(ansi reset)"
  field "Target" $"($src_dir) -> ($wsl_ssh_dest), ($win_ssh_dest)"
  field "Mode" "run"
  field "Rule" "latest file by prefix"
  print ""

  # Ensure both SSH target directories exist.
  if not ($wsl_ssh_dest | path exists) { mkdir $wsl_ssh_dest }
  if not ($win_ssh_dest | path exists) { mkdir $win_ssh_dest }

  let key_map = {
    "yuhanjin_tycs": "id_ty"
    "yuhanjin_wuzh": "id_wz"
    "yuhanjin_hf": "id_hf"
  }

  $key_map | transpose prefix target_name | each {|rule|
    let pattern_str = ($src_dir | path join ($rule.prefix + "*"))
    let matches = (try { ls ($pattern_str | into glob) } catch { [] })

    if ($matches | is-empty) {
      status "SKIP" $"No file found for prefix: ($rule.prefix)"
      return
    }

    # Select the newest downloaded key for this prefix.
    let latest_file = ($matches | sort-by modified -r | first)
    let src_path = $latest_file.name

    field "Key" $"($src_path | path basename) -> ($rule.target_name)"

    let wsl_target = ($wsl_ssh_dest | path join $rule.target_name)
    cp -f $src_path $wsl_target
    chmod 600 $wsl_target

    let win_target = ($win_ssh_dest | path join $rule.target_name)
    cp -f $src_path $win_target

    try { chmod 600 $win_target }
    status "OK" $"Copied key: ($rule.target_name)"
  }

  status "OK" "SSH key sync accomplished."
}