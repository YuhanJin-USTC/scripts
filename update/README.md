# Update Workflows

This directory groups Arch Linux package updates, Panabit iWAN route updates,
and GitHub repository publication. Their shared location does not imply a
shared safety mode.

## Arch Linux

```bash
# Preview
bash update/update_archlinux.sh

# Apply
bash update/update_archlinux.sh --run
```

Preview lists available official and AUR updates. Real mode updates the keyring,
official packages, and AUR packages. It is state-changing and may invoke
`sudo`.

## iWAN Routes

```bash
# Preview DNS and managed-route changes
bash update/update_iwan_routes.sh

# Apply after exiting Panabit iWAN
bash update/update_iwan_routes.sh --run
```

The updater resolves configured cluster IPv4 addresses and manages only its
owned `/32` routes. It preserves unrelated custom routes and settings. Real
mode requires custom-route mode and refuses to write while
`mobile_client` is running.

Route state and route-only backups are stored below
`%LOCALAPPDATA%\update_iwan_routes`. Backups are not removed automatically.
Preview reads the live Windows configuration and performs DNS queries.

## GitHub Repository Update

```bash
nu update/update_git.nu /path/to/folder "Commit message"
```

This workflow is real-only. An existing repository must be on `main`; other
branches and detached HEAD are refused before network access or mutation.
The configured `origin` takes precedence over the local directory name. Without
`origin`, the existing `YuhanJin-USTC/<directory-name>` convention is used.
The remote repository must already exist. A new local repository starts on
`main`; this command never renames an existing branch.

After checking the remote, it may add `origin`, stage all files, commit and push
`main`. A clean tree only pushes existing commits. Review the entire target
before using it. Tool_Project development uses short feature branches and
reviewed pull requests; use explicit Git commands there instead of this helper.

The Nushell command is `update_git`; it replaces the old `git_update` name.

## Safety and Validation

Use `bash -n` for Bash wrappers, `nu --ide-check 100` for
`update_git.nu`, and the Windows PowerShell parser for
`update_iwan_routes.ps1`. Help is safe only after verifying that parsing
returns before dependencies and external reads.

Check Git publication guards with an isolated fake `git` command and temporary
directories: non-main/detached refusal before remote access, origin precedence,
missing-origin fallback, clean-tree handling and external failure propagation.
Never use a real repository or network endpoint for these checks.

Do not run package updates, DNS/config previews, iWAN writes, Git commands, or
network operations merely to validate an edit.
