#!/usr/bin/env nu

# Syncs specific files from a remote directory directly to a local destination (flat structure).
# Logic: remote:src_dir/prefix*suffix -> local/prefix*suffix
def main [
  remote: string # SSH host (e.g., "user@server")
  src_dir: string # Remote source directory
  dest: path # Local destination (WSL path)
  prefix?: string # File prefix pattern (e.g., "bz")
  suffix?: string # File suffix pattern (e.g., ".sdf")
  --dry-run (-n) # Preview changes without downloading
] {
  # Ensure local directory exists
  if not ($dest | path exists) {
    mkdir $dest
  }

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

  # Base flags: archive, compress, skip owner/group (for WSL/NTFS)
  mut args = ["-amz" "-v" "--no-o" "--no-g"]

  if $dry_run {
    $args = ($args | append ["--dry-run"])
    print $"(ansi yellow)[DRY RUN] Command to be executed:(ansi reset)"
  }

  # Construct final command arguments
  let final_args = ($args | append $rules | append $remote_src | append $dest)

  # Execute rsync
  try {
    ^rsync ...$final_args
    print $"(ansi green)Sync completed successfully.(ansi reset)"
  } catch {
    print $"(ansi red)Sync failed.(ansi reset)"
    exit 1
  }
}
