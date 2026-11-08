# Runtime Instructions

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
  clean, or reinterpret existing simulation results. The timestamp has one-second resolution. Check the target before launch and stop if the result directory already exists.
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

## Figure Browser Runtime Invariants

- `run_matlab_browser.sh` is a Bash wrapper called by the Nushell alias run_matlab_browser for $HOME/Tool_Project/Figure_Browser (source root matlab_html).
  Read HOME without changing it; keep the public alias and explicit `APP_DIR`.
  Do not discover paths or read research metadata; invoke `start.sh` with `exec bash`.
- Preserve `-h`/`--help`, `--open`, and `--no-open`. Parse help and invalid
  options before external reads; open the browser by default and let
  `--no-open` take precedence.
- Keep new instances in the foreground and leave instance reuse, build
  compatibility, locks, exit status, and signals to the app launcher.
- Do not install, rebuild, repair locks, stop an existing service, or add
  background management through this wrapper. Keep the app and its data outside
  this script repository's write scope.

## Validation

- Run `bash -n run_pic.sh`.
- Run `bash -n run_jupyter.sh` and `bash -n jupyter_job.sh`.
- Run `bash -n run_matlab_browser.sh`; check help and invalid arguments without
  invoking the app, then use temporary fixtures for paths, exit status, and
  signals. A live app start or browser-opening reuse check requires explicit
  authorization.
- Inspect help, target/input/MPI guards, image checks, command construction,
  bind paths, and output placement statically.
- Inspect cluster selection, resource/path guards, Job-ID ownership checks,
  token handling, tunnel binding, signal behavior, and exact cleanup paths.
- Do not launch Apptainer, MPI, EPOCH, Smilei, Smilei-Spin, SSH, Slurm,
  JupyterLab, or a browser for validation unless the user explicitly authorizes
  the exact external test.

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
