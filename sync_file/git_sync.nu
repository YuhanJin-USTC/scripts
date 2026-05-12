#!/usr/bin/env nu

# Universal script to sync local directory to GitHub.
# Logic: auto-detect remote repository existence before pushing.
def main [
  target_dir: path     # Local directory path to sync
  message?: string     # Optional commit message
] {
  # [1/5] Validate local directory
  if not ($target_dir | path exists) {
    print $"(ansi red)Error: Path ($target_dir) not found.(ansi reset)"
    exit 1
  }

  let folder_name = ($target_dir | path basename)
  let github_user = "YuhanJin-USTC"
  let remote_url = $"https://github.com/($github_user)/($folder_name).git"

  cd $target_dir

  # [2/5] Ensure it is a git repository
  if not (".git" | path exists) {
    print $"(ansi yellow)Notice: ($folder_name) is not a git repo. Initializing...(ansi reset)"
    ^git init
  }

  # [3/5] Check if remote repository exists on GitHub
  print $"  -> Checking remote: ($remote_url)"
  try {
    # Use ls-remote to check existence without cloning
    ^git ls-remote $remote_url | ignore
    print $"(ansi green)  -> Validated: Remote repository exists.(ansi reset)"
  } catch {
    print $"(ansi red)Error: Repository '($folder_name)' not found on GitHub account ($github_user).(ansi reset)"
    print "  -> Please create the repo on GitHub first or check the folder name."
    exit 1
  }

  # [4/5] Sync remote configuration
  let current_remotes = (^git remote)
  if ($current_remotes | is-empty) {
    ^git remote add origin $remote_url
    print $"  -> Added remote origin: ($remote_url)"
  }

  # [5/5] Execute sync operations
  let commit_msg = ($message | default $"Sync ($folder_name) - (date now | format date '%Y-%m-%d %H:%M')")
  let status = (git status --porcelain)

  if ($status | is-empty) {
    print "  -> [Notice] Working tree clean. Checking for unpushed commits..."
    try {
      ^git push origin main
      print "=== Sync Accomplished ==="
    } catch {
      print $"(ansi yellow)  -> No new changes to push.(ansi reset)"
    }
    return
  }

  print "  -> Committing and pushing changes..."
  try {
    ^git add .
    ^git commit -m $commit_msg
    # Ensure local branch is named main
    ^git branch -M main
    ^git push -u origin main
    print "=== Sync Accomplished ==="
  } catch {
    print $"(ansi red)Error: Git push failed. Please check network or SSH keys.(ansi reset)"
    exit 1
  }
}
