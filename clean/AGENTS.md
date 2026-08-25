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
<!-- digest: 495b19a971d7b9b9af14663fdb4e74e31ef626d7e19a9c856f7fa4b1b28f080e -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, build, or Git mutations without explicit user authorization."
- `framework-authority`: "Use Research Workflow 0.2.2 journal-only Case authority and the unversioned researchctl CLI; historical migrate and migrate-tombstone records remain readable, schema-1 per-Case files and migration commands are unsupported, every multi-device Case write must match the latest synchronized journal head digest, and external synchronization requires explicit user authorization."
- `indexing`: "Treat .research-workflow/index.sqlite3 as local, derived, rebuildable cache only; it is never portable authority."
- `propagation`: "Use exact allowlisted targets, explicit scope approval, and a digest-bound policy apply while preserving unmanaged AGENTS bytes."
- `recording`: "Restore compact context first and record one risk-tiered checkpoint at the most specific owner; unsupported scientific status remains unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through exact knowledge links or explicit user requests."

<!-- research-workflow:policy:end -->
