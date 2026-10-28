#!/usr/bin/env nu

# Publish main through its configured remote.
def status-label [label: string] {
  match $label {
    "OK" => $"(ansi green)OK(ansi reset)"
    "SKIP" => $"(ansi yellow)SKIP(ansi reset)"
    "ERROR" => $"(ansi red)ERROR(ansi reset)"
    _ => $label
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

def field [name: string value: string] {
  print $"($name): ($value)"
}

def check-command [command: string] {
  if ((which $command) | is-empty) {
    status "ERROR" $"Command not found: ($command)."
    exit 1
  }
}

def git-output [args: list<string> action: string] {
  let result = (do { ^git ...$args } | complete)
  if $result.exit_code != 0 {
    status "ERROR" $"($action) failed with code ($result.exit_code)."
    exit $result.exit_code
  }

  $result.stdout | str trim
}

def run-git [args: list<string> action: string] {
  ^git ...$args
  let exit_code = $env.LAST_EXIT_CODE
  if $exit_code != 0 {
    status "ERROR" $"($action) failed with code ($exit_code)."
    exit $exit_code
  }
}

def print-header [target: string remote_url: string] {
  print ""
  print $"(ansi cyan)GitHub sync(ansi reset)"
  field "Target" $target
  field "Mode" "run"
  field "Rule" "main only, use origin, commit changes, push main"
  field "Remote" $remote_url
  print ""
}

def main [
  target_dir: path     # local directory path to sync
  message?: string     # optional commit message
] {
  let target = ($target_dir | path expand)

  if not ($target | path exists) {
    status "ERROR" $"Path not found: ($target)."
    exit 1
  }

  if (($target | path type) != "dir") {
    status "ERROR" $"Target is not a directory: ($target)."
    exit 1
  }

  check-command "git"

  cd $target

  let folder_name = ($target | path basename)
  let github_user = "YuhanJin-USTC"
  let existing_repo = (".git" | path exists)
  let current_remotes = if $existing_repo {
    git-output ["remote"] "Remote lookup" | lines
  } else {
    []
  }
  let remote_url = if "origin" in $current_remotes {
    git-output ["remote" "get-url" "origin"] "Origin lookup"
  } else {
    $"https://github.com/($github_user)/($folder_name).git"
  }

  print-header $target $remote_url

  if $existing_repo {
    let branch = (do { ^git symbolic-ref --quiet --short HEAD } | complete)
    if $branch.exit_code != 0 or ($branch.stdout | str trim) != "main" {
      status "ERROR" "Publication requires the main branch; detached HEAD and other branches are refused."
      print --stderr "  Review and switch branches explicitly; use a pull request for feature work."
      exit 1
    }
  }

  # Validate the remote before changing local Git state.
  field "Check remote" $remote_url
  let remote_check = (do { ^git ls-remote $remote_url } | complete)
  if $remote_check.exit_code != 0 {
    status "ERROR" "The selected remote is unavailable."
    print --stderr "  Check origin and access, or create the named GitHub repository first."
    exit $remote_check.exit_code
  }
  status "OK" "Remote repository exists."

  # Initialize the local repository only when needed.
  if not $existing_repo {
    print "Initializing local Git repository."
    run-git ["init" "--initial-branch=main"] "Git initialization"
    status "OK" "Local Git repository initialized."
  }

  # Attach origin when the repository has no remote configured.
  if "origin" not-in $current_remotes {
    run-git ["remote" "add" "origin" $remote_url] "Remote setup"
    status "OK" $"Added remote origin: ($remote_url)."
  }

  # Commit local changes, then push main.
  let commit_msg = ($message | default $"Sync ($folder_name) - (date now | format date '%Y-%m-%d %H:%M')")
  let git_status = (git-output ["status" "--porcelain"] "Status check")

  if ($git_status | is-empty) {
    print "Working tree clean. Pushing any unpushed commits."
    run-git ["push" "origin" "main"] "Git push"
    status "OK" "GitHub update completed."
    return
  }

  print "[1/3] Staging changes."
  run-git ["add" "."] "Git add"
  print "[2/3] Creating commit."
  run-git ["commit" "-m" $commit_msg] "Git commit"
  print "[3/3] Pushing main branch."
  run-git ["push" "-u" "origin" "main"] "Git push"
  status "OK" "GitHub update completed."
}
