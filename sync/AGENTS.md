# Sync and Transfer Instructions

## Scope

These rules apply only under `sync/` and supplement the repository-root
instructions. This domain owns NAS synchronization and cluster upload or
download. Changes confined here use `root:scripts/sync` as their V0 event
owner.

## Behavior Invariants

- `sync_files.nu`, `windows2cluster.nu`, and `cluster2windows.nu` remain
  preview-by-default. Only `--run` performs a transfer.
- Preserve the persistent NAS history at `~/.cache/sync_files.log`. Do not
  truncate, rotate, or remove it automatically.
- Do not add `rsync --delete`, broad overwrite behavior, or implicit transfer
  targets without explicit authorization and a clear warning.
- Preserve trailing-slash semantics: configured commands transfer directory
  contents rather than nesting the source directory.
- Keep mounts, local roots, cluster aliases, remote roots, SSH keepalive
  settings, include/exclude rules, and destination guards explicit.
- Treat both `exclude_rules_*` files as public behavior.
  `--all-files` must remain an explicit cluster-upload bypass.
- Keep upload source validation, unsafe-remote-directory rejection, and
  `--update`. Reject conflicting mode flags and propagate external SSH/rsync
  failures as nonzero exits.
- A real Data download or synchronization requires an explicit request. Record
  completeness evidence in the initiating writable work unit, never in Data.

## Validation

- Run `nu --ide-check 100` on each changed Nushell file.
- Review endpoints, SSH/rsync arguments, rule selection, and preview branching
  statically.
- Use only task-created temporary directories for rule fixtures.
- Do not connect to a cluster or NAS for routine validation. Even an rsync dry
  run may read external state and requires an explicitly scoped task.

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
