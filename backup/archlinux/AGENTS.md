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
<!-- digest: 53b828bcd3473143cd53c8eb3790393d6fec47f065abe2b14e0e167f32b593b7 -->
## Managed Research Workflow Policy

- `case-confirmation`: "A Case target does not imply a Case edit. For explicit registration or simulation-definition changes, finish files/checks, show the saved preview, actually ask and await the user, then apply the exact plan. A digest is not consent; unchanged accepted definitions add no revision."
- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, build, or Git mutations without explicit user authorization."
- `framework-authority`: "Use Research Workflow 0.2.3 and the unversioned researchctl CLI. Preserve journal-only Case authority, original Event fields, historical migrate/tombstone bindings, immutable streams, and fail-closed forks."
- `indexing`: "Treat SQLite and saved plans as device-local derived state. Queries may refresh the disposable index; never synchronize it or use it as authority."
- `multi-device`: "Synchronize and check portable authority before context or any portable write after switching devices, including event-only work. Keep local TOML/device/paths, upgrade devices sequentially, and stop old metadata writers until local acceptance. External sync remains separately authorized."
- `propagation`: "Preview pending policy semantics, exact targets and differences; obtain real user approval of the stable digest, record it through policy approve, then apply. Preserve cumulative device approvals and unmanaged AGENTS bytes; Data/Notes and body patches require exact separate scope."
- `recording`: "Restore bounded Case, Study, Project, or exact root/path memory. Record one substantive result as an event at the most specific owner; retain purpose, result, accepted reasons, validation level and limits in existing summary/evidence. Do not log ordinary Q&A or create empty membership or pending queues."
- `workspace-routing`: "Resolve local access through verified roots and explicit mappings. Logical memory may be queried without a local mapping, but new writes require local registration. Keep Data read-only and Notes access within exact authorized links/sections."

<!-- research-workflow:policy:end -->
