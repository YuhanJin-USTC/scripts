# Runtime Instructions

## Scope

These rules apply only under `run/` and supplement the repository-root
instructions. Changes confined here use `root:scripts/run` as their V0 event
owner.

## PIC Runtime Invariants

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

## Jupyter Runtime Invariants

- `run_jupyter.sh` is the WSL entry for real Slurm-backed Jupyter sessions.
  Preserve explicit `start`, `connect`, `status`, and `stop` subcommands.
- Keep cluster roots, partitions, accounts, QoS values, the
  `singularity/3.7.3` module, resource defaults, and fixed SIF-relative path
  explicit near the top of the controller.
- Never upload, replace, rebuild, or delete a SIF. A missing remote image must
  stop before state-directory creation or job submission and show the separate
  upload command.
- Resolve the requested Jupyter root remotely. It must exist below the
  configured user root; never expose `/` or accept an escaping path.
- Submit `jupyter_job.sh` through `sbatch` standard input. Do not persist a
  second script copy on the cluster.
- Keep Jupyter token authentication enabled. Store tokens only in private
  per-job state, never show them in normal output, and bind the local tunnel
  only to `127.0.0.1`.
- Validate the current user, numeric Job ID, job name, and private state before
  `connect`, `stop`, or `scancel`. Never cancel an unrelated job.
- Ctrl-C cancels the exact active Jupyter job. An unexpected tunnel or network
  failure preserves the job for `connect`; an initial start failure cancels the
  newly submitted job.
- Remove only per-job state and runtime paths created by this workflow and mark
  exact removal commands with `CODEX_TEMP_CLEANUP=1`. Preserve private logs for
  diagnosis and never touch research data.

## Validation

- Run `bash -n run_pic.sh`.
- Run `bash -n run_jupyter.sh` and `bash -n jupyter_job.sh`.
- Inspect help, target/input/MPI guards, image checks, command construction,
  bind paths, and output placement statically.
- Inspect cluster selection, resource/path guards, Job-ID ownership checks,
  token handling, tunnel binding, signal behavior, and exact cleanup paths.
- Do not launch Apptainer, MPI, EPOCH, Smilei, Smilei-Spin, SSH, Slurm,
  JupyterLab, or a browser for validation unless the user explicitly authorizes
  the exact external test.

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
