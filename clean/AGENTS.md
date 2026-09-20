# Cleanup Instructions

## Scope

These rules apply only under `clean/` and supplement the repository-root
instructions. Changes confined here use `root:scripts/clean` as their V0 event
owner.

## Behavior Invariants

- Default mode only enumerates candidates. Real deletion requires both
  `--run` and the exact typed confirmation `DELETE`.
- Preserve protected path parts, protected extensions, broad-target guards,
  no-symlink traversal, explicit junk rules, and deepest-directory-first
  removal.
- A file with no extension remains protected. Source, scripts, PIC inputs,
  templates, papers, configuration, archives, backups, credentials, and common
  research-data formats must not become candidates accidentally.
- Report any failed deletion as a failure; never print a final `[OK]` after a
  partial cleanup.
- Test rule changes only with task-created temporary files. Never use user data,
  research paths, mounted drives, or external storage as cleanup fixtures.

## Validation

- Run `nu --ide-check 100 clean_files.nu`.
- For rule changes, inspect preview output against a dedicated temporary
  fixture.
- Do not exercise `--run` unless the user authorizes the exact temporary
  deletion paths.

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
