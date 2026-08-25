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
<!-- digest: 495b19a971d7b9b9af14663fdb4e74e31ef626d7e19a9c856f7fa4b1b28f080e -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, build, or Git mutations without explicit user authorization."
- `framework-authority`: "Use Research Workflow 0.2.2 journal-only Case authority and the unversioned researchctl CLI; historical migrate and migrate-tombstone records remain readable, schema-1 per-Case files and migration commands are unsupported, every multi-device Case write must match the latest synchronized journal head digest, and external synchronization requires explicit user authorization."
- `indexing`: "Treat .research-workflow/index.sqlite3 as local, derived, rebuildable cache only; it is never portable authority."
- `propagation`: "Use exact allowlisted targets, explicit scope approval, and a digest-bound policy apply while preserving unmanaged AGENTS bytes."
- `recording`: "Restore compact context first and record one risk-tiered checkpoint at the most specific owner; unsupported scientific status remains unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through exact knowledge links or explicit user requests."

<!-- research-workflow:policy:end -->
