# Runtime Launchers

This domain contains local PIC launchers, the WSL controller for scheduled
JupyterLab sessions on configured clusters, and the local Figure_Browser
entry point.

## PIC Runs

`run_pic.sh` is the unified launcher for EPOCH, Smilei, and Smilei-Spin
Apptainer runs.

## Usage

```bash
bash run/run_pic.sh \
  <epoch1d|epoch2d|epoch3d|smilei|smilei_spin> \
  <input_file> [mpi_procs]
```

Examples:

```bash
bash run/run_pic.sh epoch2d /path/to/input.deck 8
bash run/run_pic.sh smilei /path/to/namelist.py 4
```

The Nushell aliases `run_epoch_1d`, `run_epoch_2d`, `run_epoch_3d`,
`run_smilei`, and `run_smilei_spin` preselect the corresponding target.

## Behavior

Each invocation requires one input and accepts an optional positive MPI process
count. It creates an isolated timestamped `Results_*` directory below the
invocation directory and preserves the exact input used. EPOCH retains the
original filename plus the container-required `input.deck`.

The EPOCH targets use only the Generic images `epoch_epoch1d.sif`,
`epoch_epoch2d.sif`, and `epoch_epoch3d.sif`. Photon Probe and QED sources
and SIFs remain outside this workflow and untouched.

The launcher is real-only. It has no dry-run mode and must not be used for
validation.

## Cluster JupyterLab

Open JupyterLab on a Slurm compute node from WSL:

```bash
run_jupyter start <wzcluster|tycluster|hfcluster> [remote_dir] \
  [--cpus 8] [--mem 120G] [--time 2-00:00:00] [--partition NAME]
```

The optional remote directory defaults to the configured cluster root. It must
already exist below that root. The controller submits one Slurm job, waits for
JupyterLab, opens an SSH tunnel bound to local `127.0.0.1`, and launches the
Windows default browser. Keep the WSL terminal open while using JupyterLab.

Manage an existing session with its numeric Job ID:

```bash
run_jupyter status <cluster> [job_id]
run_jupyter connect <cluster> <job_id>
run_jupyter stop <cluster> <job_id>
```

`status` never prints the Jupyter token. `connect` restores a tunnel after a
network interruption. Ctrl-C in an active `start` or `connect` session closes
the tunnel and cancels that exact Jupyter job. An unexpected tunnel failure
keeps the job for a later `connect`.

Configured defaults are:

| Cluster | Root | Partition | Account | QoS |
| --- | --- | --- | --- | --- |
| `wzcluster` | `/work/home/yuhanjin` | `wzhcnormal` | `ac58qn21ek` | `user_yuhanjin` |
| `tycluster` | `/work/home/yuhanjin` | `tyhcnormal` | `shiyin` | `user_yuhanjin` |
| `hfcluster` | `/public/home/yuhanjin` | `hfacnormal04` | `ac58qn21ek` | `user_yuhanjin` |

Each cluster must already contain
`Code_Program/Post_Process/Epoch/epoch_jupyter.sif` below its configured root.
The controller never uploads or replaces the image. If the image is missing,
upload it separately:

```bash
win2clst tycluster \
  /home/yuhanjin/Code_Program/Post_Process/Epoch \
  /work/home/yuhanjin/Code_Program/Post_Process/Epoch \
  --run --all-files

win2clst hfcluster \
  /home/yuhanjin/Code_Program/Post_Process/Epoch \
  /public/home/yuhanjin/Code_Program/Post_Process/Epoch \
  --run --all-files
```

Private runtime state and logs live below
`<cluster-root>/.cache/epoch_jupyter/`. State and per-job runtime files are
removed when the job exits; private logs remain for diagnosis. Jupyter keeps
token authentication enabled and only the local side of the tunnel is exposed
to the browser.

## Figure_Browser

Run from any directory in Nushell:

```nu
run_matlab_browser
run_matlab_browser --no-open
run_matlab_browser --help
```

The alias calls `run_matlab_browser.sh`, which forwards to
`/home/yuhanjin/Tool_Project/Figure_Browser/start.sh`. The app path is explicit in
`APP_DIR` near the top of the wrapper. Use the existing Arch WSL environment
with Node 26 and an already configured, complete app build. The public
`run_matlab_browser` alias is retained after the project directory rename.

The command opens the browser by default. `--open` is also accepted;
`--no-open` takes precedence even when both flags are supplied. A new instance
runs in the foreground: keep its terminal open and press Ctrl-C to stop it.
A compatible existing instance is reused and the new command exits; the
original terminal continues to own that service.

The wrapper preserves the app launcher's exit status and signal handling.
It does not install packages, build the app, repair locks, stop an existing
service, or manage a background process. An incompatible port owner remains
running and the app reports the error.

The alias lives in
`/home/yuhanjin/dot_files/nushell/.config/nushell/config.nu`. New Nushell
sessions load it through the existing configuration link; no Stow operation is
needed. This entry does not add a Bash alias.

## Validation

Run:

```bash
bash -n run/run_pic.sh
bash -n run/run_jupyter.sh
bash -n run/jupyter_job.sh
bash -n run/run_matlab_browser.sh
bash run/run_jupyter.sh --help
bash run/run_matlab_browser.sh --help
```

Inspect target selection, argument guards, image checks, command construction,
bind paths, Job-ID ownership checks, and cleanup paths statically. Do not launch
Apptainer, MPI, a PIC code, SSH, Slurm, JupyterLab, or a browser merely to
validate an edit. A live Jupyter check requires explicit authorization for the
cluster, resource request, remote writes, browser launch, and cleanup.

For the Figure Browser wrapper, inspect argument forwarding and use temporary
synthetic entry points to check paths, exit status, and signals. A live start or
browser-opening reuse check requires explicit authorization; never stop an
existing service as part of wrapper validation.
