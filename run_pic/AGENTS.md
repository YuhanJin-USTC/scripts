# PIC Runtime Instructions

## Scope

These rules apply only under `run_pic/` and supplement the repository-root
instructions. Changes confined here use `root:scripts:run_pic` as their V0
event owner.

## Runtime Invariants

- Every runner is a real compute workflow with no dry-run mode. Do not execute
  it without an explicit request naming the input and intended run.
- Preserve the configured SIF/executable pairing, one required input path, the
  optional positive MPI process count, and the current Apptainer requirement.
- Create an isolated timestamped `Results_*` directory below the invocation
  directory and preserve the exact input used. EPOCH runners must retain both
  the original filename and the container-required `input.deck`.
- Keep outputs inside the isolated result directory. Do not overwrite, merge,
  clean, or reinterpret existing simulation results.
- Treat changes to MPI invocation, bind paths, executables, input staging, or
  result naming as reproducibility changes and document them explicitly.

## Validation

- Run `bash -n` on every changed runner.
- Inspect help flow, input and MPI guards, image checks, command construction,
  bind paths, and output placement statically.
- Do not launch Apptainer, MPI, EPOCH, Smilei, or Smilei-Spin as a validation
  step.

<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
