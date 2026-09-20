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
<!-- digest: 53b828bcd3473143cd53c8eb3790393d6fec47f065abe2b14e0e167f32b593b7 -->
## Managed Research Workflow Policy

- `case-confirmation`: "A Case target does not imply a Case edit. For explicit registration or simulation-definition changes, finish files/checks, show the saved preview, actually ask and await the user, then apply the exact plan. A digest is not consent; unchanged accepted definitions add no revision."
- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, build, or Git mutations without explicit user authorization."
- `framework-authority`: "Use Research Workflow 0.2.3 and the unversioned researchctl CLI. Preserve journal-only Case authority, original Event fields, historical migrate/tombstone bindings, immutable streams, and fail-closed forks."
- `indexing`: "Treat SQLite and saved plans as device-local derived state. Queries may refresh the disposable index; never synchronize it or use it as authority."
- `multi-device`: "Synchronize and check portable authority before context or any portable write after switching devices, including event-only work. Keep local TOML/device/paths, upgrade devices sequentially, and stop old metadata writers until local acceptance. External sync remains separately authorized."
- `propagation`: "Preview pending policy semantics, exact targets and differences; obtain real user approval of the stable digest, record it through policy approve, then apply. Preserve cumulative device approvals and unmanaged AGENTS bytes; Data/Notes and body patches require exact separate scope."
- `recording`: "Restore bounded Case, Study, Project, or exact root/path memory. Record one substantive result as an event at the most specific owner; retain purpose, result, accepted reasons, validation level and limits in existing summary/evidence. Do not log ordinary Q&A or create empty membership or pending queues."
- `workspace-routing`: "Resolve local access through verified roots and explicit mappings. Logical memory may be queried without a local mapping, but new writes require local registration. Keep Data read-only and Notes access within exact authorized links/sections."

<!-- research-workflow:policy:end -->
