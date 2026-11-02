# Arch Linux Backup and Restore

Two Bash entry points handle Arch/WSL configuration recovery. They run by
default; `--preview` is read-only. Output follows the Nushell scripts: colored
title, Target/Mode/Rule, stage numbers and status labels. Redirected output and
`NO_COLOR` use plain text.

## Files

| File | Purpose |
| --- | --- |
| `archlinux/backup.sh`, `restore.sh` | Backup and recovery order |
| `archlinux/src/backup_set.py` | Set and archive validation, temporary ownership, file rollback and Stow |
| `archlinux/src/rebuild_tools.py` | Published-source checks and pinned downloads/builds |
| `archlinux/src/nvim_state.py`, `nvim_plugins.lua` | Editor lifecycle and isolated validation |
| `archlinux/src/mason_tools.py` | Original-path Mason reconstruction |
| `archlinux/src/rayfile_state.py` | Managed Rayfile installation and legacy snapshots |
| `archlinux/src/backup_crypto.py`, `topiary_dependencies.py` | Private GPG lifetime and legacy ELF dependency checks |
| `archlinux/data/github-current/` | The current complete backup |
| `archlinux/data/legacy-incomplete-20261031/` | Existing historical data |

The top-level `archlinux/nvim_state.py` and `archlinux/nvim_plugins.lua` are
relative links into `src/`. Existing editor commands and the Arch update script
use these paths. Both Bash entry points resolve their helpers from `src/`.

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

On a fresh Arch device with Git and the target account `yuhanjin`, run this as
that user when the scripts destination is absent:

```bash
git clone https://github.com/YuhanJin-USTC/scripts.git /home/yuhanjin/scripts
cd /home/yuhanjin/scripts
```

On an existing device, synchronize existing projects first. Backup and restore
read the public `YuhanJin-USTC/scripts` and `YuhanJin-USTC/dot_files`
repositories over HTTPS. Existing SSH recipes work and local remotes keep their
configured fetch and push settings. Git URL rewrites that redirect a project
transfer must be reviewed. A global Git proxy at `127.0.0.1:7890` requires a
running local proxy when used. A fresh clone needs no such setting.

`Research_Workflow` requires GitHub authentication. Restore tries the target
account's SSH identity with strict host checking. If the account lacks a usable
identity or a known GitHub host, restore can use the encrypted backup's
`.ssh/id_github` and `known_hosts` in
`/tmp/arch-restore-user.<random>/github-ssh/` (directory 0700, files 0600).
Only the Research_Workflow source checks and fetch receive this identity.
Restore removes the copy when those operations finish and on ordinary failure
or catchable interruption. Conflicting host keys stop preflight. When the
account does not yet exist, restore uses the saved key pairs directly from
private payload staging.

```bash
bash backup/archlinux/restore.sh --preview
sudo bash backup/archlinux/restore.sh
sudo bash backup/archlinux/restore.sh --set /absolute/path/to/github-current
sudo bash backup/archlinux/restore.sh --keep-local-workflow
# If this device has the configured local HTTP proxy listening:
sudo bash backup/archlinux/restore.sh --use-tool-proxy
```

Without `--set`, the fixed `data/github-current` set is selected automatically.
Running restore authorizes the listed managed replacements, package operations,
pinned downloads/builds, Stow links and validated editor activation. There are
no per-file replacement questions. GPG/sudo authentication remains necessary.

1. Verify and privately stage the selected archives. Check existing projects
   for unpublished work, stage pinned commits and check credentials, authority
   and target differences before deploying files.
2. Restore selected system configuration, prepare the target account and apply
   the recorded system defaults.
3. Install official packages and any recorded AUR packages. Pacman and yay
   show their native transaction output and prompts.
4. Rebuild the selected Neovim, Topiary and Rayfile candidates. Deploy project
   fast-forwards, home configuration and credentials. A matching complete
   checkout can supply file contents after the remote publication check.
5. Preflight and deploy the managed Stow links.
6. Install staged tools, reconstruct the original Mason paths, validate the
   real editor and activate the verified generation. Check formatter and
   linter records.
7. Check and restore the default login shell.
8. Remove invocation staging and show component results.

The terminal uses numbered stages and indented subtask lines. Plugin, parser
and Mason counts follow the selected tasks. Treesitter keeps two concurrent
jobs and streams native diagnostics. Transient archive and Git failures can
retry three times with the affected artifact or commit in each message.
Authentication and checksum failures stop recovery. `--use-tool-proxy`
enables the configured local HTTP proxy for tool downloads.

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

Backup assembles a set in `archlinux/data/<set-id>/` before atomic publication.
Its private scratch space is `/tmp/arch-backup.<random>/`. Restore uses
`/tmp/arch-restore-payload.<random>/` for checked payloads and its file journal,
`/tmp/arch-restore-user.<random>/` for target-user helpers, sources, builds and
its tool journal, and `/tmp/arch-restore-yay.<random>/` for an optional yay
bootstrap. The private GPG home belongs to `/tmp/arch-crypto.<random>/`.

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
