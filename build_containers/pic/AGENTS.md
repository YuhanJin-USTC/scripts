# PIC Container Instructions

## Scope

These rules apply only under `build_containers/pic/` and supplement the
container and repository-root instructions. Changes confined here use
`root:scripts/build_containers/pic` as their V0 event owner.

## PIC Invariants

- Keep environment-image builds, program-image builds, and smoke tests as
  separate stages with explicit EPOCH, Smilei, and Smilei-Spin target records.
- EPOCH builders use only Generic source
  `/home/yuhanjin/Source_Code/Epoch/Epoch/epoch` and Generic images
  `epoch_epoch1d.sif`, `epoch_epoch2d.sif`, and `epoch_epoch3d.sif`.
  Photon Probe and QED assets remain outside this workflow and untouched.
- Preserve explicit source, environment image, output image, compiler, HDF5,
  job-count, executable, and template configuration.
- Keep `pic_env_defs/`, `pic_defs/`, and `pic_test_inputs/` separate.
- Package source only inside the temporary build directory. Do not create
  rendered definitions or source archives beside stable templates.
- Keep smoke inputs minimal and deterministic. Successful test directories are
  removed; failed directories are reported and retained for diagnosis.

## Validation

- Run `nu --ide-check 100` on changed Nushell files.
- Review smoke-input syntax, dimensions, termination time, and image/command
  pairing statically.
- Do not run a real PIC build, Apptainer/Singularity test, MPI process, or
  simulation merely to validate an edit.

<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
