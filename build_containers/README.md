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
`/home/yuhanjin/Source_Code/Epoch/Epoch/epoch` and produce the Generic images
`epoch_epoch1d.sif`, `epoch_epoch2d.sif`, and `epoch_epoch3d.sif`.
Photon Probe and QED sources and images are outside this workflow and remain
untouched.

## PIC Smoke Tests

```bash
nu build_containers/pic/test_pic_images.nu all --dry-run
nu build_containers/pic/test_pic_images.nu smilei_spin
```

The inputs under `pic/pic_test_inputs/` exercise startup, input parsing,
executable linkage, MPI/HDF5 availability, and a short time loop. Successful
temporary test directories are removed. Failed test directories are retained
and reported for diagnosis.

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
