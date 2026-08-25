# Post-Processing Container Instructions

## Scope

These rules apply only under `build_containers/post_process/` and supplement
the container and repository-root instructions. Changes confined here use
`root:scripts/build_containers/post_process` as their V0 event owner.

## Post-Processing Invariants

- Keep the EPOCH Jupyter builder and `post_process_defs/` independent from PIC
  environment, program-image, and smoke-test assets.
- Preserve the configured base image, PyPI index, APT packages, fixed Python
  package versions, output path, and `--force` overwrite rule unless the user
  explicitly changes them.
- Keep the image immutable and free of research data and notebooks.
- Real SDF reads, transfers, cluster execution, scheduler use, and Jupyter
  tunnels are separate authorized workflows.
- After an explicitly authorized real build, validation may inspect the SIF,
  run `pip check`, import configured modules, and check JupyterLab version.
  Do not run those operations merely to validate source edits.

## Validation

- Run `nu --ide-check 100` on the builder.
- Compare every template placeholder with the renderer record and review the
  configured package pins statically.
- A dry run reads configured paths and requires authorization. Never perform a
  real image build solely for validation.

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
