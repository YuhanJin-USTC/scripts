# Arch Linux Backup and Restore

Two Bash entry points handle Arch/WSL configuration recovery. They run by
default; `--preview` is read-only. Output follows the Nushell scripts: colored
title, Target/Mode/Rule, stage numbers and status labels. Redirected output and
`NO_COLOR` use plain text.

## Files

| File | Purpose |
| --- | --- |
| `archlinux/backup.sh`, `restore.sh` | Backup and recovery order |
| `archlinux/backup_set.py` | Set/archive validation, temporary ownership, file rollback and Stow |
| `archlinux/rebuild_tools.py` | Published-source checks and pinned downloads/builds |
| `archlinux/nvim_state.py`, `nvim_plugins.lua` | Managed editor lifecycle and real editor validation |
| `archlinux/mason_tools.py` | Internal original-path Mason reconstruction |
| `archlinux/rayfile_state.py` | Managed Rayfile installation and legacy snapshots |
| `archlinux/backup_crypto.py`, `topiary_dependencies.py` | Private GPG lifetime and legacy ELF dependency checks |
| `archlinux/data/github-current/` | The single current complete backup |

## Backup

First commit and push each changed project separately: `dot_files`,
`Research_Workflow`, and the scripts source. Backup never commits or pushes.
The generated backup is then committed/pushed in scripts as usual.

```bash
bash backup/archlinux/backup.sh --preview
bash backup/archlinux/backup.sh
```

Backup checks uncommitted/untracked project content and verifies local branch
commits against the actual remote in disposable Git storage. The scripts
backup-output directory is excluded from its source cleanliness check. Plugin
checks inspect tracked source changes only; untracked/ignored plugin runtime
files never block backup and are never archived. Backup does not hash the entire
installed editor. Personal plugin source edits must still be published first. Network/authentication failure stops
backup; cached remote-tracking refs are not proof of publication.

Format 2 keeps the following small components:

| Component | Content |
| --- | --- |
| `packages.tar.gz` | Package names, observed versions, core Python dependencies and default shell |
| `system.tar.gz`, `home.tar.gz` | Selected system and home configuration |
| `credentials.tar.gz.gpg` | Encrypted SSH/GPG and effective Git/rclone/Codex credentials |
| `rebuild.tar.gz` | Project commits; editor runtime/plugin/parser pins; Mason receipts and Python pins; Rayfile URL/checksums; Topiary crate version/checksum and Nu grammar revision |
| `manifest.json`, `COMPLETE` | Component integrity and completion |

Projects, plugin trees, binaries and their Git directories are not archived.
Active Neovim configuration must match the published dot_files configuration,
except the generated active lazy-lock.json: its exact text is included in the
small reconstruction record and applied only inside the rebuilt editor. Only
Git-tracked Neovim configuration paths are selected; local caches, swap files
and other untracked configuration files are not inventoried or copied.
SSH/GPG capture uses a durable-key/configuration allowlist, excluding sockets,
logs, known_hosts.old, random_seed, locks and incidental files. Live keyboxd
databases require a consistent export and are refused. Topiary cache inventories
and unrelated private npm package records are not captured.
Research_Workflow's `workspace.toml`, local cache/plans, research data and
Codex personal configuration remain outside the portable backup.

A failed backup removes its own incomplete set and plaintext staging, keeping
the preceding complete publication. Successful publication atomically replaces
the current set. Old tracked binary archives are not removed by editing
`.gitignore`; Git history replacement is a separate approved operation.

## Restore

On the target device, synchronize any existing projects first. Use the updated
scripts checkout; a format-1 scripts snapshot never overwrites this runner.
GitHub access must work before online reconstruction. For a missing target
account, the preflight can use privately staged SSH key/public-key pairs and
saved known_hosts; it never disables host verification.

```bash
bash backup/archlinux/restore.sh --preview
sudo bash backup/archlinux/restore.sh
sudo bash backup/archlinux/restore.sh --set /absolute/path/to/github-current
sudo bash backup/archlinux/restore.sh --keep-local-workflow
```

Without `--set`, the fixed `data/github-current` set is selected automatically.
Running restore authorizes the listed managed replacements, package operations,
pinned downloads/builds, Stow links and validated editor activation. There are
no per-file replacement questions. GPG/sudo authentication remains necessary.

1. Validate/decrypt the selected set in private staging. Check existing projects
   for unpublished work before the first configuration replacement.
2. Stage the recorded project commits. After verifying publication, restore
   reads a complete matching checkout locally. Otherwise it fetches the pinned
   objects with their file contents from GitHub before checkout. Existing
   projects must match the origin and branch and allow a fast-forward. A
   matching HEAD needs no deployment Git transaction. Errors identify the
   project, the commit and the Git operation.
3. Restore selected system settings and install Arch/AUR dependencies. Arch
   packages follow current repositories; this is not a historical OS image.
4. Rebuild editor and Topiary candidates and download Rayfile in staging before
   deploying home configuration. The results table shows selected tools as
   `pending` until this stage runs. Optional tools with a null source record
   show `skipped`. Missing pins/downloads stop recovery.
5. Deploy project/configuration changes and Stow links. Existing ignored local
   files and device settings remain in existing checkouts. Effective encrypted
   Git/rclone content must agree with its published Stow source; disagreement
   stops preflight instead of asking which version to overwrite.
6. Restore Topiary and the original-path Mason tools, validate the real editor,
   and activate it automatically. Mason compares the compiler-resolved source
   with the receipt, including version overrides; it never falls back to latest.

Research_Workflow records and device identity are not replaced by another
machine's snapshot. Different populated authority stops legacy recovery;
`--keep-local-workflow` explicitly preserves the complete existing checkout.
Online recovery refuses a commit that would replace existing authority records.
New devices receive the project but still need their own verified
`workspace.toml` and normal framework acceptance; the result reports this as
uncovered rather than claiming a usable registered device.

The Rayfile download is pinned to
`https://wuzh01.hpccube.com:65015/efile/share/fasttrans-client.tar.gz`, archive
SHA256 `ef4592c4701073b96e166f533364cb049be7e1ebbd093254fcac4ce4847140f2`.
A changed vendor archive fails checksum validation. The executable and launcher
stay at `~/.local/share/rayfile-runtime` and `~/.local/bin/rayfile-c`.
Transfers, credentials and native Raysync state are untouched.

## Failure and cleanup

Each invocation owns its staging and a temporary rollback journal. Successful
restore removes the journal and staging. Ordinary errors and catchable signals
restore replaced configuration, links and managed tool paths, then remove the
invocation's downloads, plaintext, build output and temporary originals.
Errors stay on the terminal; no home-level `*_restore_backup_*` directories or
per-run `arch-recovery` records are created. Pacman and yay use a separate,
root-owned package cache under `/tmp/arch-restore-pacman.*`. Its mode is 0755
so Pacman's download user can reach its own `download-*` subdirectory. AUR
builds and decrypted configuration use private staging. The exit handler
removes the package cache on success or failure.

Package upgrades, account creation and generated system databases are not
rolled back as file transactions. A rollback failure preserves the originals
and prints their exact location. Changed/untrusted cleanup identities are never
recursively deleted. Power loss/SIGKILL can prevent cleanup; existing remnants
from other invocations require exact review and are not swept by globs.
All task-owned cleanup is marked `CODEX_TEMP_CLEANUP=1`.

## Compatibility and validation

Complete format-1 sets remain readable, including their offline Neovim and
Rayfile payloads. `--legacy /absolute/path/to/old/archlinux` retains the legacy
exit-3 incomplete guarantee. Old backup payloads and old failed-run directories
are not deleted during this source-code update.

Use `bash -n`, Python `compile()` with `-B`, inspected help and isolated helper
fixtures. Fixtures cover actual Mason source resolution, Git publication checks,
real Stow, rollback and failure/signal cleanup. Do not run full recovery, package
installation, real editor builds or transfers merely to test script changes.

Standalone editor maintenance remains available through `nvim_state.py`:
`status`, `prepare`, `validate`, `activate`, `rollback`, `launcher-upgrade`,
`backup`, `stage`, `restore`, `equivalent`, `tools` and `formatter-check`.
Standalone preparation/activation retain their explicit preview/identity gates;
restore supplies the already-authorized transaction. Private npm installation,
browser/HTML/PDF export and real transfer/resume testing remain outside recovery.
