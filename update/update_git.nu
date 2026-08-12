#!/usr/bin/env nu

# Sync a local directory to the matching GitHub repository.
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
  field "Rule" "init if needed, commit changes, push main"
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

  let folder_name = ($target | path basename)
  let github_user = "YuhanJin-USTC"
  let remote_url = $"https://github.com/($github_user)/($folder_name).git"

  print-header $target $remote_url

  # Validate the remote before changing local Git state.
  field "Check remote" $remote_url
  let remote_check = (do { ^git ls-remote $remote_url } | complete)
  if $remote_check.exit_code != 0 {
    status "ERROR" $"Repository '($folder_name)' not found on GitHub account ($github_user)."
    print --stderr "  Create the repo on GitHub first or check the folder name."
    exit $remote_check.exit_code
  }
  status "OK" "Remote repository exists."

  cd $target

  # Initialize the local repository only when needed.
  if not (".git" | path exists) {
    print "Initializing local Git repository."
    run-git ["init"] "Git initialization"
    status "OK" "Local Git repository initialized."
  }

  # Attach origin when the repository has no remote configured.
  let current_remotes = (git-output ["remote"] "Remote lookup" | lines)
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

  print "[1/4] Staging changes."
  run-git ["add" "."] "Git add"
  print "[2/4] Creating commit."
  run-git ["commit" "-m" $commit_msg] "Git commit"
  print "[3/4] Updating main branch."
  run-git ["branch" "-M" "main"] "Branch update"
  print "[4/4] Pushing main branch."
  run-git ["push" "-u" "origin" "main"] "Git push"
  status "OK" "GitHub update completed."
}
