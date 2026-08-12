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
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
