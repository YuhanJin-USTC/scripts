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
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
