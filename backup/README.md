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

## Validation

Use `bash -n` and inspect help only after confirming its early-return path.
Review archive handling, quoting, privilege checks, traps, ownership, modes,
rollback paths, and temporary cleanup statically. Do not run package, GPG,
Stow, restore, or Git operations for routine validation.
