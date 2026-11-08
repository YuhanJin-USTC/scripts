# Cluster Key Transfer Instructions

## Credential Invariants

- `tsf_clst_key.nu` is a real-only credential deployment workflow. It selects
  the newest source matching each configured prefix and force-copies it to
  fixed WSL and Windows SSH targets.
- Preserve explicit source prefixes, destination names, fixed target
  directories, and restrictive WSL permissions unless the user changes the
  account workflow.
- Treat a platform-specific permission operation that cannot apply as an
  explicit `[WARN]` or `[SKIP]`; do not silently swallow it.
- Do not execute the script for validation. Do not list matching key files,
  read key contents, copy keys, create SSH directories, or expose key material
  without explicit authorization.

## Validation

- Run `nu --ide-check 100 tsf_clst_key.nu`.
- Review matching, newest-file selection, destination construction, overwrite
  behavior, permissions, error propagation, and output redaction statically.
- There is no safe runtime dry run.

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
