# Container Build Instructions

Use root:scripts/build_containers for shared work or its exact pic or post_process child for confined work. This file owns both sets of differences.

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
  `/home/yuhanjin/Source_Code/Epoch/Epoch_2025/epoch` and Generic images
  `epoch_epoch1d.sif`, `epoch_epoch2d.sif`, and `epoch_epoch3d.sif`.
  Photon Probe and QED assets remain outside this workflow and untouched.
- Use Intel MPI 2021.3.0 for all PIC targets, with the existing GNU compiler
  backends and parallel HDF5 built against the same MPI. Keep the standard
  target and image names; do not retain separate MPI trial targets.
- Keep cluster provider selection and host-library bindings in the Slurm
  examples, not in container image defaults.
- Set a default FI_PROVIDER_PATH for the bundled Intel MPI provider
  directory in PIC environment images and smoke-test commands. Preserve
  explicit provider paths and fabric selection.
- Run smoke tests with OMP_NUM_THREADS=1. Keep production thread settings
  outside the smoke-test workflow.
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

- Review package pins and renderer placeholders statically. Apply the shared validation and dry-run authorization rules above.

<!-- research-workflow:policy:start -->
<!-- digest: 255425630765de0b777c8b315a1469fc936fca419187535850dcd16888fc5f5d -->
## Managed Research Workflow Policy

- `case-confirmation`: "Case ownership alone changes no definition. For registration, definition or lifecycle changes, finish files/checks, show the saved plan, ask and await consent, then apply its digest. Equal definitions add no revision."
- `external-operations`: "Require explicit task authorization for Git, network/API, SSH, cluster, transfer, sync, simulation, MATLAB, builds, containers and SIF operations."
- `framework-authority`: "Use Research Workflow 0.2.4 and its unversioned CLI. Preserve journal-only Cases, original Event fields, migrate/tombstone bindings and immutable streams. Stop on forks."
- `indexing`: "SQLite and saved plans are disposable device-local state. Queries may refresh SQLite. Never sync either or use it as authority."
- `multi-device`: "After a switch, preserve local work and separately authorize sync. Check portable authority with doctor, event merge and validate before context or any portable write. Keep TOML, paths and identity local. Upgrade sequentially with old writers stopped through acceptance."
- `propagation`: "Show pending semantics, exact targets, diffs and stable digest. After user approval, record it with policy approve and apply that digest. Preserve cumulative approvals and unmanaged bytes. Data, Notes and body patches need separate exact scope."
- `recording`: "Restore compact Case, Study, Project or exact root/path context. Record one substantive result at its closest eligible owner, with purpose, result, accepted reasons, checks and limits in summary/evidence. Skip ordinary discussion, empty membership and pending queues."
- `workspace-routing`: "Use verified roots and explicit mappings. Unmapped logical memory is readable. Local access and new writes need registration. Data stays read-only. Scope Notes to exact links/sections and writes to explicit requests."

<!-- research-workflow:policy:end -->
