# Cleanup Instructions

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
- Use only approved task-created temporary fixtures for cleanup checks.

## Validation

- Run `nu --ide-check 100 clean_files.nu`.
- For rule changes, inspect preview output against a dedicated temporary
  fixture.
- Do not exercise `--run` unless the user authorizes the exact temporary
  deletion paths.

<!-- research-workflow:policy:start -->
<!-- digest: 255425630765de0b777c8b315a1469fc936fca419187535850dcd16888fc5f5d -->
## Managed Research Workflow Policy

- `case-confirmation`: "Case ownership alone changes no definition. For registration, definition or lifecycle changes, finish files/checks, show the saved plan, ask and await consent, then apply its digest. Equal definitions add no revision."
- `external-operations`: "Require explicit task authorization for Git, network/API, SSH, cluster, transfer, sync, simulation, MATLAB, builds, containers and SIF operations."
- `framework-authority`: "Use Research Workflow 0.2.4 and its unversioned CLI. Preserve journal-only Cases, original Event fields, migrate/tombstone bindings and immutable streams. Stop on forks."
- `indexing`: "SQLite and saved plans are disposable device-local state. Queries may refresh SQLite. Never sync either or use it as authority."
- `multi-device`: "After a switch, preserve local work and separately authorize sync. Check portable authority with doctor, event merge and validate before context or any portable write. Keep TOML, paths and identity local. Upgrade sequentially with old writers stopped through acceptance."
- `propagation`: "Show pending semantics, exact targets, diffs and stable digest. After user approval, record it with policy approve and apply that digest. Preserve cumulative approvals and unmanaged bytes. Data, Notes and body patches need separate exact scope."
- `recording`: "Restore compact Case, Study, Project or exact root/path context. Record one substantive result at its closest eligible owner, with purpose, result, accepted reasons, checks and limits in summary/evidence. Skip ordinary discussion, empty membership and pending queues."
- `workspace-routing`: "Use verified roots and explicit mappings. Unmapped logical memory is readable. Local access and new writes need registration. Data stays read-only. Scope Notes to exact links/sections and writes to explicit requests."

<!-- research-workflow:policy:end -->
