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
