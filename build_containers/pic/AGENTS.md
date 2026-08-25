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
<!-- digest: 495b19a971d7b9b9af14663fdb4e74e31ef626d7e19a9c856f7fa4b1b28f080e -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, build, or Git mutations without explicit user authorization."
- `framework-authority`: "Use Research Workflow 0.2.2 journal-only Case authority and the unversioned researchctl CLI; historical migrate and migrate-tombstone records remain readable, schema-1 per-Case files and migration commands are unsupported, every multi-device Case write must match the latest synchronized journal head digest, and external synchronization requires explicit user authorization."
- `indexing`: "Treat .research-workflow/index.sqlite3 as local, derived, rebuildable cache only; it is never portable authority."
- `propagation`: "Use exact allowlisted targets, explicit scope approval, and a digest-bound policy apply while preserving unmanaged AGENTS bytes."
- `recording`: "Restore compact context first and record one risk-tiered checkpoint at the most specific owner; unsupported scientific status remains unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through exact knowledge links or explicit user requests."

<!-- research-workflow:policy:end -->
