# PIC Runtime Instructions

## Scope

These rules apply only under `run/` and supplement the repository-root
instructions. Changes confined here use `root:scripts/run` as their V0 event
owner.

## Runtime Invariants

- `run_pic.sh` is a real compute workflow with no dry-run mode. Do not execute
  it without an explicit request naming the target, input, and intended run.
- Preserve the target selector, one required input path, optional positive MPI
  process count, configured SIF/executable pairing, and Apptainer requirement.
- EPOCH runners use only Generic images `epoch_epoch1d.sif`,
  `epoch_epoch2d.sif`, and `epoch_epoch3d.sif`. Photon Probe and QED assets
  remain outside this workflow and untouched.
- Create an isolated timestamped `Results_*` directory below the invocation
  directory and preserve the exact input. EPOCH must retain the original name
  and the container-required `input.deck`.
- Keep outputs inside the isolated result directory. Never overwrite, merge,
  clean, or reinterpret existing simulation results.
- Treat target selection, MPI invocation, bind paths, executables, input
  staging, and result naming as reproducibility behavior.

## Validation

- Run `bash -n run_pic.sh`.
- Inspect help, target/input/MPI guards, image checks, command construction,
  bind paths, and output placement statically.
- Do not launch Apptainer, MPI, EPOCH, Smilei, or Smilei-Spin for validation.

<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
