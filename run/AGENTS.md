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
<!-- digest: 495b19a971d7b9b9af14663fdb4e74e31ef626d7e19a9c856f7fa4b1b28f080e -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, build, or Git mutations without explicit user authorization."
- `framework-authority`: "Use Research Workflow 0.2.2 journal-only Case authority and the unversioned researchctl CLI; historical migrate and migrate-tombstone records remain readable, schema-1 per-Case files and migration commands are unsupported, every multi-device Case write must match the latest synchronized journal head digest, and external synchronization requires explicit user authorization."
- `indexing`: "Treat .research-workflow/index.sqlite3 as local, derived, rebuildable cache only; it is never portable authority."
- `propagation`: "Use exact allowlisted targets, explicit scope approval, and a digest-bound policy apply while preserving unmanaged AGENTS bytes."
- `recording`: "Restore compact context first and record one risk-tiered checkpoint at the most specific owner; unsupported scientific status remains unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through exact knowledge links or explicit user requests."

<!-- research-workflow:policy:end -->
