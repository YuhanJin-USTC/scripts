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
    ├── rayfile_state.py
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

## Rayfile

The official fast-transfer client uses the same user-runtime snapshot pattern
as Neovim. It does not enter the Pacman/AUR lists or add a new Stow package.
The reviewed release is **6.7.8.12**, Linux x86_64. System libraries remain
managed by Arch. The archive checksum pins the inspected download; it is not
a vendor signature.

| Content | Location |
| --- | --- |
| Executable, official readme, manifest, checksums | `~/.local/share/rayfile-runtime/` |
| Shell entry point | `~/.local/bin/rayfile-c` |
| Portable program snapshot | `backup/archlinux/data/rayfile.tar.gz` |
| Preserved installation during restore | `~/rayfile_restore_backup_*/` |
| Native client logs | `~/.config/Raysync/` |

The existing Bash and Nushell PATH already includes `~/.local/bin`. The
launcher forwards all arguments without changing the working directory,
proxy settings, source paths or destinations. Do not run the vendor installer:
it copies two unmanaged binaries into `/usr/local`.

### First installation

Run from the `scripts` repository in Bash:

```bash
(
  set -e
  rayfile_tmp=$(mktemp -d /tmp/rayfile-setup.XXXXXXXX)
  trap 'CODEX_TEMP_CLEANUP=1 rm -rf -- "$rayfile_tmp"' EXIT
  curl --fail --location --show-error \
    --proto '=https' --proto-redir '=https' \
    --noproxy wuzh01.hpccube.com --connect-timeout 15 --max-time 300 \
    --output "$rayfile_tmp/fasttrans-client.tar.gz" \
    'https://wuzh01.hpccube.com:65015/efile/share/fasttrans-client.tar.gz'
  python3 -B backup/archlinux/rayfile_state.py install \
    "$rayfile_tmp/fasttrans-client.tar.gz"
)
python3 -B backup/archlinux/rayfile_state.py verify
rayfile-c --version
```

`--noproxy` applies only to this download host. It does not change persistent
proxy configuration. Installation verifies the reviewed archive and executable
hashes, checks the version, and refuses an existing runtime or launcher.
A changed upstream archive requires reviewing the release and updating the
installer constants; never bypass the checksum to fetch an unknown version.

### Backup and recovery

The normal `backup.sh` now creates `data/rayfile.tar.gz` after the Neovim
snapshot. It includes only the four managed runtime files, launcher and
snapshot manifest. It validates the installed version and all file checksums
before atomically replacing a previous archive. Logs, credentials, research
data and unfinished transfers are excluded. Keep this archive and the helper
with the other backup payloads when synchronizing devices.

If Rayfile is absent and no older archive exists, backup reports `[SKIP]`.
A partial installation, modified launcher, checksum mismatch or stale archive
with no installed client stops backup, retaining the previous archive.

`restore.sh` stages the archive and helper before repository synchronization,
checks paths, architecture and checksums, and restores Rayfile as the target
user after Neovim. It uses the saved binary without network access or a package
installation. Existing runtime and launcher are moved to a unique safety
directory; deployment failure attempts to roll back those two paths. Transfer
state is untouched. Old backups without `rayfile.tar.gz` explicitly skip this
step and retain any existing Rayfile installation.

Rayfile-only backup and recovery are also available; these commands do not run
the full Arch backup or restore:

```bash
python3 -B backup/archlinux/rayfile_state.py backup backup/archlinux/data/rayfile.tar.gz

(
  set -e
  rayfile_stage=$(mktemp -d /tmp/rayfile-restore.XXXXXXXX)
  trap 'CODEX_TEMP_CLEANUP=1 rm -rf -- "$rayfile_stage"' EXIT
  mkdir "$rayfile_stage/input"
  python3 -B backup/archlinux/rayfile_state.py stage \
    backup/archlinux/data/rayfile.tar.gz "$rayfile_stage/input"
  python3 -B backup/archlinux/rayfile_state.py restore "$rayfile_stage/input"
)
```

The optional `--home /absolute/path` on install, backup, restore and verify
selects an explicit target home. It also supports isolated temporary-home
validation without changing the process HOME. Safety backups are retained.

### Logs and unfinished transfers

A network-isolated startup probe of 6.7.8.12 observed these native log files:

```text
~/.config/Raysync/RayFileClient-YYYYMMDD.log
~/.config/Raysync/debug.log
~/.config/Raysync/license_0.log
```

`--version` exits without creating them. Logs start during normal connection
setup; they are device-local and are not Stow configuration or snapshot input.
The client also probes optional `raysync.ini`, `cloud-storage.ini` and
`config/config.ini` beside the executable; the official bundle supplies none.
Adding such files requires reviewing their contents and the snapshot allowlist.

No successful transfer was performed during installation. Static inspection
found `.raysync.downloading`, `.raysync.temp.downloading`,
`.raysync.check.data` and `.raysync.original.` strings; a download helper
appends `.raysync.downloading` to a file path. These are evidence of temporary
file naming, not proof of which paths this server enables. The actual resume
files, directory and successful resume behavior remain unverified until an
explicitly authorized transfer. Do not treat `-db` or `config/rs.db` as a
verified resume-file destination, and do not auto-remove unfinished transfers.

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

Check `rayfile_state.py` with `compile()` and local `--help`. Use the real
reviewed binary with temporary `--home` directories for snapshot round trips,
repeated preservation, changed launchers, corrupt archives, duplicate members,
symlinks, path traversal, architecture rejection and deployment rollback.
Only `--version` is used by its runtime check. Network probes require separate
task authorization and must use an isolated network and temporary paths, never
real credentials, research data or live backup payloads.
