# Arch Backup and Restore Instructions

## Scope

These rules apply only under `backup/archlinux/` and supplement the
repository-root instructions. Changes confined here use
`root:scripts/backup/archlinux` as their V0 event owner.

## Protected State

- `backup.sh` is real-only. It rewrites package lists and archives, handles
  credentials through GPG, records the default shell, and inspects Git state.
- `restore.sh` is a root-only disaster-recovery pipeline. It restores system
  and home configuration, installs packages, restores credentials, creates or
  changes users, runs Stow, and force-syncs configured repositories.
- Treat `data/`, encrypted archives, `pkg_lists/`, default-shell records,
  SSH/GPG material, and application credentials as protected user content.
- Keep the home archive and restore path aligned, including the optional
  home-level `/home/yuhanjin/AGENTS.md`.
- Preserve timestamped safety backups and the exclusion of `.ssh/config`,
  which is owned by dot_files/Stow. Never remove safety backups automatically.
- Keep temporary restore paths unique and clean them on success and failure.
  Cleanup may target only temporary paths created by that invocation.
- Changes to forced Git synchronization, package installation, proxy use,
  privilege boundaries, credential restoration, or backup replacement require
  explicit authorization and prominent handoff notes.

## Validation

- Run `bash -n` on each changed shell script.
- Inspect help only after confirming that it returns before state-changing work.
- Review archive members, quoting, privilege guards, traps, safety backup paths,
  ownership, modes, rollback, and failure cleanup statically.
- Never run backup, restore, package, GPG, Stow, credential, or forced Git
  operations for routine validation.

<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
