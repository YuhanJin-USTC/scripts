#!/usr/bin/env nu

def main [] {
  # path
  let src_dir = ("/mnt/d/Download/Edge" | path expand)
  let win_ssh_dest = "/mnt/c/Users/17865/.ssh"
  let wsl_ssh_dest = ("~/.ssh" | path expand)

  # check dir
  if not ($wsl_ssh_dest | path exists) { mkdir $wsl_ssh_dest }
  if not ($win_ssh_dest | path exists) { mkdir $win_ssh_dest }

  # map prefix to file name
  let key_map = {
    "yuhanjin_tycs": "id_ty"
    "yuhanjin_wuzh": "id_wz"
    "yuhanjin_hf": "id_hf"
  }

  print "sync ssh file"
  print $"Search Directory: ($src_dir)"

  $key_map | transpose prefix target_name | each {|rule|
    let pattern_str = ($src_dir | path join ($rule.prefix + "*"))
    let matches = (try { ls ($pattern_str | into glob) } catch { [] })

    if ($matches | is-empty) {
      print $"[SKIP] No file found for prefix: ($rule.prefix)"
      return
    }

    # select the latest one 
    let latest_file = ($matches | sort-by modified -r | first)
    let src_path = $latest_file.name

    print $"[PROC] Processing: ($rule.prefix)... find: ($src_path | path basename) -> target: ($rule.target_name)"

    # WSL
    let wsl_target = ($wsl_ssh_dest | path join $rule.target_name)
    cp -f $src_path $wsl_target
    chmod 600 $wsl_target

    # windows
    let win_target = ($win_ssh_dest | path join $rule.target_name)
    cp -f $src_path $win_target

    try { chmod 600 $win_target }
  }

  print "sync accomplished"
}
