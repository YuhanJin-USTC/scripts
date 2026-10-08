# Arch Linux Backup and Restore

This subsystem records selected Arch Linux WSL state and provides a
high-impact disaster-recovery workflow.

## Files

```text
backup/
├── README.md
└── archlinux/
    ├── AGENTS.md
    ├── backup.sh
    ├── restore.sh
    ├── nvim_state.py
    ├── nvim_plugins.lua
    ├── pkg_lists/
    └── data/
```

The payloads below `archlinux/data/`, package lists, encrypted archives,
default-shell record, and preserved safety backups are user content. Do not
edit, replace, inspect for convenience, or use them as fixtures.

## Backup

```bash
bash backup/archlinux/backup.sh --help
bash backup/archlinux/backup.sh
```

The backup is real-only. It rewrites the package lists and configured archives,
encrypts credential material with GPG, records the default shell, and inspects
configured repository state. The home archive includes
`/home/yuhanjin/AGENTS.md` when present. The Stow-owned `.ssh/config` is
excluded from the encrypted credential archive.

The first stage creates `data/nvim.tar.gz`. It includes the effective Neovim
configuration (following Stow links), the unchanged `lazy-lock.json`, plugin
repository URLs, installed Treesitter parser names, and the official Linux
Neovim bundle matching the source device's stable version. Configuration and
runtime checksums are saved in the same archive. A failed snapshot leaves the
previous Neovim archive intact and stops before the other backup stages.
The repository ignore rules allow this specific archive. Include it with the
updated helper scripts when committing and transferring a backup.

This stage requires Python 3.12+, Git, an installed stable Neovim, configured
plugins and parsers, and access to the official GitHub release. Linux x86_64
and aarch64 are supported; the bundle is specific to the source architecture.
Keep the normal `~/.config/nvim` and `~/.local/share/nvim` paths. Plugin commits
come from the lockfile, not from possibly different installed checkouts.

Review the exact payload paths before running. Never execute backup merely to
validate a code or documentation change.

## Restore

```bash
sudo bash backup/archlinux/restore.sh --help
sudo bash backup/archlinux/restore.sh
```

Restore is a root-only, real-only disaster-recovery pipeline. It can replace
system and home configuration after preserving timestamped safety copies,
install official and AUR packages, restore credentials, create or change the
target user, run Stow, and force-sync configured repositories.

The workflow uses the encrypted copy of `id_github` and
`ssh -F /dev/null` while bootstrapping repositories. After Stow, the global
Git configuration uses `ssh -F ~/.ssh/config`. Existing safety backups are
never removed automatically.

Stow preserves existing Git, SSH, and rclone configuration in a unique user
backup directory, then checks all packages before deploying them together.
Matching links are retained. Other conflicts stop deployment. If backup,
preflight, or deployment fails, moved files are restored where the destination
is still absent. Completed links and their original backups are retained if
deployment fails partway through. Earlier restore stages are not rolled back.

Sensitive application files are extracted into a private temporary directory
before replacing their destination. Regular archive members become local
files without writing through Stow links. Archived symbolic links retain an
existing, valid link only when its resolved target matches; missing or different
targets stop restoration. Link-only archives do not contain the linked file's
contents. Hard links and other member types are rejected. Existing parent
directories and unarchived files are preserved during credential backup.

When launched from the target `scripts` repository, restore leaves that
repository unchanged instead of resetting the running script. Synchronize it
separately after restoration. Other configured repositories retain the existing
force-sync behavior. Root and user safety directories use unique suffixes;
repeated backups of one path retain each version.

Neovim restoration is mandatory for backups made by this version. Run the
updated backup on the source device first, then transfer the backup payloads
and these scripts together. Old payloads without `nvim.tar.gz` cannot reproduce
the recorded environment. No automatic Git commit or push is performed.

The Neovim snapshot and helper scripts are staged before repository sync.
Before resetting `dot_files`, restore preserves both the effective Neovim
configuration contents and its repository source, then moves the old deployed
layout into the unique Stow safety directory. The snapshot replaces the whole
Neovim package before Stow, so obsolete files cannot survive a directory merge
and a newer remote configuration cannot replace the backed-up one.

After Stow, the new Neovim stage runs as the target user. It preserves existing
`~/.local/share/nvim/lazy`, `site`, `~/.local/share/nvim-runtime`, and
`~/.local/bin/nvim` in a unique `~/nvim_restore_backup_*` directory. It deploys
the bundled Neovim to `~/.local/share/nvim-runtime` and installs a launcher at
`~/.local/bin/nvim`, which is already first in this setup's shell PATH. The
launcher fixes both the executable and `VIMRUNTIME`. Different target versions
and locally edited plugin caches are replaced after backup, not rejected.
Arch's system Neovim package is left under Pacman's management; its later
updates do not change the selected bundled executable.

All locked plugins, including Lazy itself, are cloned and checked out at their
recorded commits. Only then does a clean Neovim process read the plugin specs,
run the supported native builds, and rebuild recorded Treesitter parsers using
the locked plugin's grammar revisions. A fresh process verifies native modules,
parser revisions, parsing and highlight queries. The script checks every plugin
HEAD and the complete configuration checksum again. It never runs `Lazy sync`,
updates the lockfile, or starts the user's init/config callbacks during recovery.
Failed downloads, builds or validation return nonzero; previous backups remain
available, and partially completed restore stages are not rolled back globally.

The Neovim stage needs network access for the recorded plugin and grammar
sources, plus the compiler, make and tree-sitter CLI from the package stages.
It supports the existing LuaSnip, FZF and Treesitter builds; unsupported custom
build hooks fail explicitly. LSP servers, formatters, Python environments and
other system packages are outside this version lock. Their existing configuration
is preserved in the snapshot, but their binaries are not made identical by
`lazy-lock.json`. Missing optional tools are not installed by this stage.

## Validation

Use `bash -n` and inspect help only after confirming its early-return path.
Review archive handling, quoting, privilege checks, traps, ownership, modes,
rollback paths, and temporary cleanup statically. Do not run package, GPG,
restore, or Git operations for routine validation. Check Stow arguments with
the installed binary and temporary packages and targets, never user
configuration. GNU Stow 2.4.1 does not collect package names after `--`;
keep package names after the options and reject names beginning with `-` or `+`.

Check `nvim_state.py` with Python's `compile()` without writing bytecode. Test
archive rejection, configuration preservation, forced replacement, launchers
and failure handling in temporary homes only. Test `nvim_plugins.lua` with real
Neovim and plugin modules, including a failed native build and parser query
errors; Neovim's process exit status alone is insufficient without explicit
error propagation. Never use the real backup payloads or installed plugin
directories as writable fixtures.
