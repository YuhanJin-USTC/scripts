# PIC Runs

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

## Validation

Run `bash -n run/run_pic.sh`. Inspect help, target selection, input and MPI
guards, image checks, command construction, bind paths, and output placement
statically. Do not launch Apptainer, MPI, EPOCH, Smilei, or Smilei-Spin merely
to validate an edit.
