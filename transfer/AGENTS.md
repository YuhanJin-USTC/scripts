# Cluster Key Transfer Instructions

## Scope

These rules apply only under `transfer/` and supplement the repository-root
instructions. Changes confined here use `root:scripts/transfer` as their V0
event owner.

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
<!-- digest: 495b19a971d7b9b9af14663fdb4e74e31ef626d7e19a9c856f7fa4b1b28f080e -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, build, or Git mutations without explicit user authorization."
- `framework-authority`: "Use Research Workflow 0.2.2 journal-only Case authority and the unversioned researchctl CLI; historical migrate and migrate-tombstone records remain readable, schema-1 per-Case files and migration commands are unsupported, every multi-device Case write must match the latest synchronized journal head digest, and external synchronization requires explicit user authorization."
- `indexing`: "Treat .research-workflow/index.sqlite3 as local, derived, rebuildable cache only; it is never portable authority."
- `propagation`: "Use exact allowlisted targets, explicit scope approval, and a digest-bound policy apply while preserving unmanaged AGENTS bytes."
- `recording`: "Restore compact context first and record one risk-tiered checkpoint at the most specific owner; unsupported scientific status remains unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through exact knowledge links or explicit user requests."

<!-- research-workflow:policy:end -->
