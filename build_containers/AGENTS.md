# Container Build Instructions

## Scope

These rules apply under `build_containers/` and supplement the repository-root
instructions. Shared changes confined here use
`root:scripts/build_containers` as their V0 event owner. Use the nearer PIC or
post-processing owner for changes confined to those subtrees.

## Shared Invariants

- `build_common.nu` owns only container-engine selection, stable
  `Target`/`Mode`/`Rule` output, template rendering, and exact temporary
  cleanup.
- Keep PIC and post-processing target records, templates, dependencies, builds,
  and tests in their separate subtrees.
- Stable definitions use `*.def.tmpl`. Render definitions only inside unique
  temporary build directories and reject unresolved placeholders.
- Builds are real by default and use `--force` for configured SIF targets.
  Preserve the `--dry-run` preview interface and show overwrite behavior.
- Remove only task-created temporary build directories, with
  `CODEX_TEMP_CLEANUP=1`. Do not pre-delete a SIF.
- Source_Code and Code_Program are independent authorization scopes. A
  configured path does not authorize modifying either root.

## Validation

- Run `nu --ide-check 100` on changed Nushell files.
- Compare every template placeholder with its renderer record.
- A dry run reads configured paths; use it only when those reads are authorized.
- Never perform a real build or smoke test solely for validation.

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
