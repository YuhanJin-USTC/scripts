#!/usr/bin/env nu

# Keep credentials and backup payloads out of cleanup.
def path-has-protected-part [path: string] {
  let parts = ($path | path split)

  if ($parts | any {|part| $part in [".git" ".ssh" ".gnupg"] }) {
    return true
  }

  ($path | str contains "/backup_archlinux/data/") or ($path | str ends-with "/backup_archlinux/data")
}

# Treat research data, source, configs, and archives as protected files.
def protected-extension? [path: string] {
  let ext = ($path | path parse | get extension | str lowercase)

  $ext in [
    py sh nu c h cpp cxx cc hpp f f90 cu jl m
    deck tmpl namelist inp in i mac cfg conf toml yaml yml json
    md tex bib sty cls org ipynb
    h5 hdf5 sdf bp bp4 bp5 vtk vti vtu csv tsv dat txt npy npz mat nc root
    gpg asc pem key pub tar gz tgz zip 7z xz bz2
  ]
}

def protected-file? [path: string] {
  let base = ($path | path basename)
  let ext = ($path | path parse | get extension)

  if ($base in [AGENTS.md Makefile makefile Dockerfile Containerfile]) {
    return true
  }

  if $ext == "" {
    return true
  }

  protected-extension? $path
}

def junk-file? [path: string] {
  let base = ($path | path basename)
  let ext = ($path | path parse | get extension | str lowercase)

  if ($base in [".DS_Store" "Thumbs.db"]) {
    return true
  }

  if ($base | str ends-with "~") {
    return true
  }

  if (protected-file? $path) {
    return false
  }

  $ext in [pyc pyo tmp temp bak swp swo]
}

def junk-dir? [path: string] {
  let base = ($path | path basename)
  $base in [__pycache__ .pytest_cache .mypy_cache .ruff_cache .ipynb_checkpoints]
}

# Refuse broad cleanup targets.
def assert-safe-target [target: string] {
  let home = ($env.HOME | path expand)
  let repo = ("/home/yuhanjin/scripts" | path expand)

  if not ($target | path exists) {
    error make {msg: $"Target does not exist: ($target)"}
  }

  if (($target | path type) != "dir") {
    error make {msg: $"Target is not a directory: ($target)"}
  }

  if $target in ["/" $home $repo] {
    error make {msg: $"Refusing to clean protected target: ($target)"}
  }
}

# Collect explicit junk candidates only.
def list-candidates [target: string] {
  let pattern = ($target | path join "**/*")
  let paths = (
    glob $pattern --no-symlink
    | where {|path| $path != $target }
    | where {|path| not (path-has-protected-part $path) }
  )

  let files = (
    $paths
    | where {|path| ($path | path type) == "file" }
    | where {|path| junk-file? $path }
    | sort
  )

  let junk_dirs = (
    $paths
    | where {|path| ($path | path type) == "dir" }
    | where {|path| junk-dir? $path }
    | sort-by {|path| $path | str length } --reverse
  )

  {files: $files, junk_dirs: $junk_dirs}
}

# Compute directories that become empty after candidate removal.
def list-empty-dirs-after [
  target: string
  files: list<string>
  junk_dirs: list<string>
] {
  let pattern = ($target | path join "**/*")
  let dirs = (
    glob $pattern --no-file --no-symlink
    | where {|path| $path != $target }
    | where {|path| not (path-has-protected-part $path) }
    | where {|path| ($path | path type) == "dir" }
    | where {|path| not (junk-dir? $path) }
    | sort-by {|path| $path | str length } --reverse
  )

  mut empty_dirs = []

  for dir in $dirs {
    let entries = (try { ls -a $dir | get name } catch { [] })
    let removable = ($files | append $junk_dirs | append $empty_dirs)

    if ($entries | all {|entry| $entry in $removable }) {
      $empty_dirs = ($empty_dirs | append $dir)
    }
  }

  $empty_dirs | sort-by {|path| $path | str length } --reverse
}

def print-list [title: string, items: list<string>] {
  print $"($title): ($items | length)"

  if not ($items | is-empty) {
    print $items
  }
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
}

def print-header [target: string dry_run: bool] {
  print ""
  print $"(ansi cyan)File clean(ansi reset)"
  print $"Target: ($target)"
  print $"Mode: (if $dry_run { 'dry-run' } else { 'run' })"
  print "Rule: explicit junk only"
  if $dry_run {
    status "DRY-RUN" "No files will be deleted."
  }
  print ""
}

def main [
  target_dir: path
  --run
] {
  let target = ($target_dir | path expand)
  let do_dry_run = not $run

  assert-safe-target $target

  let candidates = (list-candidates $target)
  let files = $candidates.files
  let junk_dirs = $candidates.junk_dirs
  let empty_dirs = (list-empty-dirs-after $target $files $junk_dirs)
  let total = (($files | length) + ($junk_dirs | length) + ($empty_dirs | length))

  print-header $target $do_dry_run
  print "File rules: *.pyc *.pyo *.tmp *.temp *.bak *.swp *.swo *~ .DS_Store Thumbs.db"
  print "Dir rules: __pycache__ .pytest_cache .mypy_cache .ruff_cache .ipynb_checkpoints"
  print "Protected: source, scripts, PIC inputs, templates, papers, configs, data, backups, keys"
  print ""

  print-list "Junk files" $files
  print-list "Junk directories" $junk_dirs
  print-list "Empty directories" $empty_dirs
  print ""

  if $total == 0 {
    status "OK" "Nothing to clean."
    return
  }

  if $do_dry_run {
    status "OK" "Dry run completed. Add --run to delete these paths."
    return
  }

  # Require a typed confirmation before deletion.
  let answer = (input "Type DELETE to permanently remove these paths: ")

  if $answer != "DELETE" {
    status "SKIP" "Operation cancelled."
    return
  }

  for file in $files {
    try {
      rm $file
    } catch {
      print $"Failed to delete file: ($file)"
    }
  }

  for dir in $junk_dirs {
    if ($dir | path exists) {
      try {
        rm -r $dir
      } catch {
        print $"Failed to remove directory: ($dir)"
      }
    }
  }

  for dir in $empty_dirs {
    if ($dir | path exists) {
      try {
        rm $dir
      } catch {
        print $"Failed to remove empty directory: ($dir)"
      }
    }
  }

  status "OK" "Cleanup complete."
}
