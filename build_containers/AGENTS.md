# Container Build Instructions

## Scope

These rules apply under `build_containers/` and supplement the repository-root
instructions. Shared changes confined here use
`root:scripts/build_containers` as their V0 event owner. Use `root:scripts/build_containers/pic` or
`root:scripts/build_containers/post_process` for work confined to that directory.
PIC and post-processing differences are owned by this file.

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

## PIC Validation

- Review smoke-input syntax, dimensions, termination time, and image/command
  pairing statically.
- Do not run a real PIC build, Apptainer/Singularity test, MPI process, or
  simulation merely to validate an edit.

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

## Post-Processing Validation

- Compare every template placeholder with the renderer record and review the
  configured package pins statically.
- A dry run reads configured paths and requires authorization. Never perform a
  real image build solely for validation.

<!-- research-workflow:policy:start -->
<!-- digest: 89d09a6994f49df8c13b524a2af6ad0acf361194fc848c001cb517be1ee3a44f -->
## Managed Research Workflow Policy

- `case-confirmation`: "A Case target does not imply a Case edit. For explicit registration or simulation-definition changes, finish files/checks, show the saved preview, actually ask and await the user, then apply the exact plan. A digest is not consent; unchanged accepted definitions add no revision."
- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, build, or Git mutations without explicit user authorization."
- `framework-authority`: "Use Research Workflow 0.2.4 and the unversioned researchctl CLI. Preserve journal-only Case authority, original Event fields, historical migrate/tombstone bindings, immutable streams, and fail-closed forks."
- `indexing`: "Treat SQLite and saved plans as device-local derived state. Queries may refresh the disposable index; never synchronize it or use it as authority."
- `multi-device`: "Synchronize and check portable authority before context or any portable write after switching devices, including event-only work. Keep local TOML/device/paths, upgrade devices sequentially, and stop old metadata writers until local acceptance. External sync remains separately authorized."
- `propagation`: "Preview pending policy semantics, exact targets and differences; obtain real user approval of the stable digest, record it through policy approve, then apply. Preserve cumulative device approvals and unmanaged AGENTS bytes; Data/Notes and body patches require exact separate scope."
- `recording`: "Restore bounded Case, Study, Project, or exact root/path memory. Record one substantive result as an event at the most specific owner; retain purpose, result, accepted reasons, validation level and limits in existing summary/evidence. Do not log ordinary Q&A or create empty membership or pending queues."
- `workspace-routing`: "Resolve local access through verified roots and explicit mappings. Logical memory may be queried without a local mapping, but new writes require local registration. Keep Data read-only and Notes access within exact authorized links/sections."

<!-- research-workflow:policy:end -->
