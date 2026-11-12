# Runtime Launchers

This domain contains local PIC launchers, PIC Slurm submission examples, the
WSL controller for scheduled JupyterLab sessions on configured clusters, and
the local Figure_Browser entry point.

## PIC Runs

`run_pic.sh` is the unified launcher for EPOCH, Smilei, and Smilei-Spin
Apptainer runs on one local host. Use the Slurm examples for multi-node runs.

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
An existing result directory causes an error before any input is copied.

The launcher sets `FI_PROVIDER_PATH` to `$I_MPI_ROOT/libfabric/lib/prov`
inside the container only when unset or empty. This also supports existing
Intel MPI SIFs whose environment omitted the provider path. Explicit provider
paths, fabric selection, and production OpenMP settings are preserved.

EPOCH binds the result directory to `/work`. Smilei and Smilei-Spin explicitly
bind it at the same absolute path and use that path as the container working
directory. The output location and result naming are unchanged.

The EPOCH targets use only the Generic images `epoch_epoch1d.sif`,
`epoch_epoch2d.sif`, and `epoch_epoch3d.sif`. Photon Probe and QED sources
and SIFs remain outside this workflow and untouched.

The launcher is real-only. It has no dry-run mode and must not be used for
validation.

## PIC Slurm Examples

Copy [epoch_jobsub.sh](jobsub/epoch_jobsub.sh) or
[smilei_jobsub.sh](jobsub/smilei_jobsub.sh) into the case directory. Fill every
`<...>` value in the active `#SBATCH` header, then edit the input and SIF paths
near the top of the script. Enable and fill the commented constraint directive
when selecting a CPU type in a mixed partition.

```bash
# Safe help from this repository
sh run/jobsub/epoch_jobsub.sh --help
sh run/jobsub/smilei_jobsub.sh --help

# Real submission from the prepared case directory
sbatch epoch_jobsub.sh
sbatch smilei_jobsub.sh
```

The scripts contain no fixed production allocation. Set total ranks to nodes
times ranks per node, and keep ranks per node times threads within the selected
node's CPU count. `SLURM_NTASKS` supplies MPI ranks and `SLURM_CPUS_PER_TASK`
supplies OpenMP threads. The scripts retain `OMP_SCHEDULE=dynamic`,
`OMP_PROC_BIND=true`, and `I_MPI_PIN_DOMAIN=omp`.

The following settings were checked through read-only SSH queries on
2026-11-11. All three sites provide `mpi/intelmpi/2021.3.0` and
`singularity/3.7.3`; the user QoS is `user_yuhanjin`.

| Cluster | Partition | CPUs/node | Constraint | Account | Provider |
| --- | --- | --- | --- | --- | --- |
| WZ | `wzacnormal` | 128 | none required | `ac58qn21ek` | `mlx` |
| WZ | `wzacnormal04` | 64 | none required | `ac58qn21ek` | `mlx` |
| WZ | `wzhcnormal` | 32 or 64 | `32core` or `64core` | `ac58qn21ek` | `mlx` |
| HF | `hfacnormal01` | 128 | none required | `ac58qn21ek` | `psm2` |
| HF | `hfacnormal02` | 128 | none required | `ac58qn21ek` | `psm2` |
| HF | `hfacnormal04` | 128 | none required | `ac58qn21ek` | `psm2` |
| TY | `tyhcnormal` | 32 or 64 | `32core` or `64core` | `shiyin` | `mlx` |

The provider defaults extend the original test script's WZ `wzacnormal`, HF
`hfacnormal04`, and TY `tyhcnormal` settings. The added partitions have not been
run-tested; available modules and libraries do not prove compute-node fabric
compatibility or performance. An explicit provider override is retained:

```bash
sbatch --export=ALL,I_MPI_OFI_PROVIDER=tcp epoch_jobsub.sh
sbatch --export=ALL,I_MPI_OFI_PROVIDER=tcp smilei_jobsub.sh
```

There is no automatic TCP fallback. One host `mpiexec` launches the container
processes. The scripts bind the host Intel MPI directory read-only, add
`/opt/hpc/software/mpi/hpcx/v2.11.0/ucx_without_rocm` for `mlx`, or bind
`/lib64/libpsm2.so.2` into the container for `psm2`. Smilei also retains
`/opt/.local/program/hdf5/lib` in the container library path.

`HOME` is `/work/home/yuhanjin` on WZ/TY and `/public/home/yuhanjin` on HF.
The scripts bind this directory at the same container path. Submit from the
case directory under that home; input and result paths use the submission
working directory. Both scripts create a new
`Results_<input>_<timestamp>_<jobid>` directory and refuse to reuse an existing
one. Slurm logs remain `out_%j.log` and `err_%j.log`.

EPOCH defaults to the Generic 3D SIF; `EPOCH_DIM` selects `1d`, `2d`, or `3d`.
The external table path is
`$HOME/Source_Code/Epoch/Epoch/epoch/epoch${EPOCH_DIM}/src/physics_packages/TABLES`.
This cluster path differs from the local `Epoch_2025` build source path.
The source deck is copied as `<input_name>_backup`; only the generated
`input.deck` receives the `__TABLE_PATH__` substitution. `USE_DATA_DIRECTORY`
contains `./`, preserving the test runner's output selection.

Smilei defaults to `input.py` and the standard Smilei SIF. The script includes
the alternate Smilei-Spin SIF path as a comment. The input is copied unchanged
into the result directory. Both examples preserve a nonzero simulation exit
status and retain failed run files for diagnosis.

Rebuild the environment and program images with the updated Intel MPI
[container workflow](../build_containers/README.md) before using these examples.
They do not build, upload, or submit anything automatically when read or when
invoked with `--help`.

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
`$HOME/Tool_Project/Figure_Browser/start.sh`. The explicit `APP_DIR` reads the
current user's HOME without changing the environment. It does not search for
directories or read Research Workflow metadata; keep it aligned with the
device's verified checkout. Use the existing Arch WSL environment
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
sh -n run/jobsub/epoch_jobsub.sh
sh -n run/jobsub/smilei_jobsub.sh
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
