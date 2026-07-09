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
  print $"[(status-label $label)] ($message)"
}

def field [name: string value: string] {
  print $"($name): ($value)"
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
  if not ($target_dir | path exists) {
    status "ERROR" $"Path not found: ($target_dir)"
    exit 1
  }

  let folder_name = ($target_dir | path basename)
  let github_user = "YuhanJin-USTC"
  let remote_url = $"https://github.com/($github_user)/($folder_name).git"

  print-header ($target_dir | path expand) $remote_url

  cd $target_dir

  # Initialize the local repository only when needed.
  if not (".git" | path exists) {
    status "SKIP" $"($folder_name) is not a git repo. Initializing."
    ^git init
  }

  # Validate the remote repository before changing local state.
  field "Check remote" $remote_url
  try {
    ^git ls-remote $remote_url | ignore
    status "OK" "Remote repository exists."
  } catch {
    status "ERROR" $"Repository '($folder_name)' not found on GitHub account ($github_user)."
    print "  Create the repo on GitHub first or check the folder name."
    exit 1
  }

  # Attach origin when the repository has no remote configured.
  let current_remotes = (^git remote)
  if ($current_remotes | is-empty) {
    ^git remote add origin $remote_url
    status "OK" $"Added remote origin: ($remote_url)"
  }

  # Commit local changes, then push main.
  let commit_msg = ($message | default $"Sync ($folder_name) - (date now | format date '%Y-%m-%d %H:%M')")
  let git_status = (git status --porcelain)

  if ($git_status | is-empty) {
    status "SKIP" "Working tree clean. Checking for unpushed commits."
    try {
      ^git push origin main
      status "OK" "Sync accomplished."
    } catch {
      status "SKIP" "No new changes to push."
    }
    return
  }

  status "OK" "Committing and pushing changes."
  try {
    ^git add .
    ^git commit -m $commit_msg
    ^git branch -M main
    ^git push -u origin main
    status "OK" "Sync accomplished."
  } catch {
    status "ERROR" "Git push failed. Please check network or SSH keys."
    exit 1
  }
}