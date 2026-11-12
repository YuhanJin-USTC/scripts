# Container Builds

Container-image workflows are divided into independent PIC and
post-processing subtrees. Both select Apptainer when available and otherwise
Singularity.

## Layout

```text
build_containers/
├── AGENTS.md
├── README.md
├── build_common.nu
├── pic/
│   ├── AGENTS.md
│   ├── bd_pic_envs.nu
│   ├── bd_pic_images.nu
│   ├── test_pic_images.nu
│   ├── pic_env_defs/
│   ├── pic_defs/
│   └── pic_test_inputs/
└── post_process/
    ├── AGENTS.md
    ├── bd_post_process_images.nu
    └── post_process_defs/
```

The PIC and post-processing pipelines share only generic output helpers and
template rendering. Their target records, definitions, dependencies, builds,
and validation remain separate.

## PIC Environment Images

Targets are `epoch`, `smilei`, and `smilei_spin`.

All PIC targets use Intel MPI 2021.3.0 on Ubuntu 20.04, installed from the
versioned `intel-oneapi-mpi-devel-2021.3.0` package. GNU compiler backends are
retained. Smilei and Smilei-Spin build parallel HDF5 1.14.5 with the same MPI.

Environment builds remove only Intel MPI's four standalone `libmpi.dbg`
files under `lib/release`, `lib/release_mt`, `lib/debug`, and `lib/debug_mt`.
MPI static libraries, shared libraries, compiler wrappers, and headers remain.
This removes detailed MPI library debug symbols, not `I_MPI_DEBUG` logging.
Smilei builds disable pip caching and remove the HDF5 source/build directory
after installation; the installed HDF5 libraries and headers remain available.

```bash
nu build_containers/pic/bd_pic_envs.nu smilei --dry-run
nu build_containers/pic/bd_pic_envs.nu smilei
```

## PIC Program Images

Targets are `epoch1d`, `epoch2d`, `epoch3d`, `smilei`, and
`smilei_spin`.

```bash
nu build_containers/pic/bd_pic_images.nu epoch2d --dry-run
nu build_containers/pic/bd_pic_images.nu epoch2d
```

Program builds archive configured local source into a unique temporary
directory, render a matching `*.def.tmpl`, and build the configured SIF with
`--force`. No rendered definition or source archive is stored beside the
templates.

EPOCH targets use only the Generic source
`/home/yuhanjin/Source_Code/Epoch/Epoch_2025/epoch` and produce the Generic images
`epoch_epoch1d.sif`, `epoch_epoch2d.sif`, and `epoch_epoch3d.sif`.
Photon Probe and QED sources and images are outside this workflow and remain
untouched.

Smilei sources are configured at
`/home/yuhanjin/Source_Code/Smilei/Smilei_2025/Smilei` and
`/home/yuhanjin/Source_Code/Smilei/Smilei_Spin_2025/Smilei_Spin`.
EPOCH exports the Intel MPI `mpif90` wrapper to both EPOCH and SDF; Smilei uses
the Intel MPI `mpicxx` wrapper through `SMILEICXX`. Existing build flags and
job counts are preserved.

After compilation, EPOCH builds remove the selected dimension's `obj` directory
and `SDF/FORTRAN/obj`, retaining that dimension's source and tables. Smilei and
Smilei-Spin builds remove the intermediate `build` directory while retaining
the top-level `smilei` and `smilei_test` executables, `src`, `scripts`, `tools`,
`makefile`, and `CMakeLists.txt`. The other configured cleanup items are
unchanged. Executable debug information is retained; no stripping or compiler
flag changes are applied. Object files must be regenerated for later rebuilds.

Rebuild each environment image before its program images when migrating from
MPICH. The standard target and SIF names are unchanged; the separate
`epoch_intelmpi` and `epoch3d_intelmpi` trial targets have been removed.
Editing these scripts does not update existing SIFs. Real builds still use
`--force` and replace the configured output image.

Cluster provider selection belongs to the
[Slurm submission examples](../run/README.md#pic-slurm-examples).
The images do not fix a fabric provider. The cluster examples use a host MPI
launcher with the matching site libraries; the local launcher continues to
use MPI inside the container.

PIC environment images set `FI_PROVIDER_PATH` to
`$I_MPI_ROOT/libfabric/lib/prov` when unset or empty. The smoke tests and local
launcher apply the same default inside the container, so existing Intel MPI
SIFs can use these entry points without rebuilding. Explicit provider paths
and fabric selection are preserved. Template changes take effect in images
only after rebuilding the environment and program images.

After a program build, `Run test` prints the matching smoke-test command with
its configured input. The builder does not execute that command.

## PIC Smoke Tests

```bash
nu build_containers/pic/test_pic_images.nu all --dry-run
nu build_containers/pic/test_pic_images.nu smilei_spin
```

The inputs under `pic/pic_test_inputs/` exercise startup, input parsing,
executable linkage, MPI/HDF5 availability, and a short time loop. Successful
temporary test directories are removed. Failed test directories are retained
and reported for diagnosis.

Smoke tests set `OMP_NUM_THREADS=1` inside the container. The dry-run command
shows this setting and the default provider-path expression. Production thread
settings and cluster provider selection remain controlled by their launchers.

## EPOCH Jupyter Post-Processing Image

The post-processing target is `epoch`.

```bash
nu build_containers/post_process/bd_post_process_images.nu epoch --dry-run
nu build_containers/post_process/bd_post_process_images.nu epoch
```

The image uses `python:3.12-slim-bookworm`, the configured Tsinghua PyPI
index, and fixed JupyterLab, ipykernel, NumPy, SciPy, Matplotlib, h5py, pandas,
and `sdfr` versions. It is written to
`/home/yuhanjin/Code_Program/Post_Process/Epoch/epoch_jupyter.sif`.

Research data and notebooks are not embedded. SDF reads, transfers, cluster
execution, scheduler use, and Jupyter tunnels are separate explicitly
authorized workflows.

## Safety and Validation

The builders and smoke tests are real by default; `--dry-run` is the preview.
A dry run still reads configured paths and requires authorization for those
roots. Builds use `--force` and can replace the configured SIF.

Run `nu --ide-check 100` on changed Nushell files. For templates, compare
every placeholder with its renderer record and confirm no placeholder remains
unresolved. Do not run a real container build or smoke test solely for
validation.
