# scripts

Personal research-automation toolkit for laser-plasma theory and simulation
workflows. It covers Arch Linux on WSL, Windows/NAS/cluster file movement,
backup and restore, PIC container builds and runs, and GPU subtitle processing.

This is a script-first personal repository, not a portable software package.
The explicit paths, cluster aliases, image names, job counts, and target records
near the top of each script are intentional: they keep daily research workflows
easy to inspect and edit.

## Design Goals

- Save time on repeated research and workstation tasks.
- Keep commands transparent and manually editable.
- Preview external changes where the current interface supports it.
- Protect credentials, backup payloads, source trees, simulation data, and
  reproducibility.
- Keep EPOCH, Smilei, and Smilei-Spin build/run configuration explicit.

## Environment

The configured environment is:

- Arch Linux under WSL.
- Repository path: `/home/yuhanjin/scripts`.
- Windows mounts: `/mnt/c` and `/mnt/d`.
- NAS mounts: `/mnt/y` and `/mnt/z/金虞焓`.
- SSH aliases: `hfcluster`, `tycluster`, and `wzcluster`.

There is no global installer or repository-wide dependency command. Install only
the tools required by the workflow you use.

| Workflow | Required tools or resources |
| --- | --- |
| Core scripts | Bash, Nushell, standard Linux utilities |
| iWAN route update | WSL, `powershell.exe`, `wslpath`, Panabit iWAN 2.1.3 |
| NAS/cluster transfer | `rsync`, OpenSSH, configured mounts/SSH aliases |
| Arch maintenance | `pacman`, `yay`; `checkupdates` is optional |
| Backup/restore | `tar`, `gpg`, Git, `stow`, Arch package tools |
| PIC image build | Container engine, `sudo`, source/image paths |
| PIC run | `apptainer` and the configured SIF image |
| ASR/MT | `singularity`, NVIDIA GPU access in WSL, local ASR/MT images |
| Subtitle burn-in | `ffmpeg` in addition to the ASR/MT requirements |

The Python helpers are designed to run inside their corresponding containers;
their packages are not managed as a host-side Python environment.

## Before First Use

1. Place the repository at `/home/yuhanjin/scripts`, or update every intentional
   absolute reference before running anything.
2. Review the editable variables at the top of the relevant script.
3. Confirm required Windows/NAS mounts, SSH aliases, source trees, and SIF images.
4. Read `--help` and use the documented preview mode when one exists.
5. Inspect every real-only workflow before execution.

## Safety Model

The scripts do not all share the same default mode. Check this table before
running a command:

| Workflow | Default | Real action |
| --- | --- | --- |
| `update_archlinux/update.sh` | Preview | Add `--run` |
| `update_iwan_routes/update_iwan_routes` | Preview | Exit iWAN, then add `--run` |
| `sync_files/sync_files.nu` | Preview | Add `--run` |
| `sync_files/windows2cluster.nu` | Preview | Add `--run` |
| `sync_files/cluster2windows.nu` | Preview | Add `--run` |
| `clean_files/clean_files.nu` | Preview | Add `--run`, then type `DELETE` |
| PIC image build scripts | **Real build** | Add `--dry-run` to preview |
| PIC smoke-test script | **Real test** | Add `--dry-run` to preview |
| Backup/restore, key/Git sync, PIC run, ASR/MT | **Real** | No dry run |

Important boundaries:

- Sync scripts do not use `rsync --delete`.
- iWAN route updates modify Panabit settings only after `--run`, and refuse to
  write while the client is running.
- Cluster upload excludes common large output formats unless `--all-files` is
  supplied.
- Backup writes fixed package-list and archive paths under `backup_archlinux/`.
- Restore changes the system, installs packages, restores credentials, and
  force-synchronizes configured Git repositories. It must be reviewed and run
  as root only when a full restore is intended.
- SSH key sync uses forced copies to fixed WSL and Windows key paths.
- Git sync can initialize a repository, stage all changes, commit, rename the
  branch to `main`, and push.
- PIC builds use `build --force` and can replace an existing SIF image.
- Subtitle burn-in uses FFmpeg overwrite mode for the generated output name.

## Quick Start

These commands inspect help or preview behavior without intentionally performing
the corresponding real workflow:

```bash
# Arch/AUR update preview
./update_archlinux/update.sh

# iWAN cluster-route preview
./update_iwan_routes/update_iwan_routes

# NAS sync preview
nu sync_files/sync_files.nu all

# Cluster upload preview
nu sync_files/windows2cluster.nu hfcluster /path/to/case Simulation/case

# Cluster download preview
nu sync_files/cluster2windows.nu hfcluster /remote/path /local/path bz .sdf

# Junk cleanup preview
./clean_files/clean_files /path/to/project

# PIC program-image build preview
nu build_singularity_image/bd_pic_images.nu smilei --dry-run

# PIC image smoke-test preview
nu build_singularity_image/test_pic_images.nu all --dry-run

# Real-only workflow help
bash backup_archlinux/backup.sh --help
./backup_archlinux/restore.sh --help
./run_pic/smilei_run.sh --help
```

Container previews still validate configured executables and paths, so they can
fail safely when the local PIC environment has not been prepared.

## Usage Reference

Run all examples from the repository root unless noted otherwise.

### Arch Linux WSL

Preview official-repository and AUR updates:

```bash
./update_archlinux/update.sh
```

Perform the real update only after reviewing the preview:

```bash
./update_archlinux/update.sh --run
```

The backup workflow has no dry-run mode. It records package lists, creates
selected configuration archives, encrypts credential data with GPG, and checks
the Git state of core directories:

```bash
bash backup_archlinux/backup.sh
```

`backup_archlinux/restore.sh` is a root-only disaster-recovery pipeline. Review
the complete script and payloads under `backup_archlinux/` before running it.
It preserves replaced paths in timestamped safety directories. The temporary
`yay` build directory is unique per run and is removed when that install step
exits, including after a failure. Official-package installation performs a
full system upgrade. If a Pacman package transaction fails, the restore
retries once through Arch's official geo mirror with a pipe-backed alternate
Pacman configuration. The retry does not modify the active mirror list or
write a temporary configuration file.

### iWAN Cluster Routes

The updater resolves the IPv4 addresses for the configured Hefei, Wuzhen,
Taiyuan, and SCNet hosts. It replaces only the `/32` routes managed by the
script and preserves other CIDRs already present in Panabit iWAN.

```bash
# Preview DNS and route changes
./update_iwan_routes/update_iwan_routes

# Apply after exiting Panabit iWAN from the Windows system tray
./update_iwan_routes/update_iwan_routes --run

# Show help
./update_iwan_routes/update_iwan_routes --help
```

The script reads the current Windows user's configuration from
`%APPDATA%\com.panabit\panabit_client\shared_preferences.json`. State and
route-only backups are stored below `%LOCALAPPDATA%\update_iwan_routes`.
No backup is created when the routes are unchanged, and backups are not removed
automatically.

This workflow targets the Panabit iWAN 2.1.3 settings format and requires
custom-route mode. DNS, MTU, login data, and unrelated settings are not changed.
If Panabit changes the internal format, the updater stops without writing;
review it again after an iWAN upgrade.

### NAS Sync

```bash
nu sync_files/sync_files.nu <target|all> [--run]
```

Configured targets are `dot_files`, `scripts`, `Code_Program`, `Simulation`,
`Source_Code`, `Under_Graduate`, and `Matlab`. Without `--run`, rsync runs in
preview mode. Terminal status is also appended to
`~/.cache/sync_files.log` for later sync review; this history is retained.

Examples:

```bash
# Preview one target
nu sync_files/sync_files.nu Simulation

# Run all configured syncs
nu sync_files/sync_files.nu all --run
```

NAS exclusion rules live in `sync_files/exclude_rules_nas_only`.

### Cluster Upload

```bash
nu sync_files/windows2cluster.nu \
  <hfcluster|tycluster|wzcluster> \
  <local_directory> \
  <remote_directory> \
  [--run] [--all-files]
```

A relative remote directory is resolved below the selected cluster's configured
root. An absolute remote directory is used unchanged. The default rule file is
`sync_files/exclude_rules_cluster_upload`; `--all-files` bypasses it. Uploads use
`--update` and do not delete remote files.

```bash
# Preview source/config upload
nu sync_files/windows2cluster.nu \
  hfcluster /home/yuhanjin/Simulation/case_a Simulation/case_a

# Perform the same upload
nu sync_files/windows2cluster.nu \
  hfcluster /home/yuhanjin/Simulation/case_a Simulation/case_a --run
```

### Cluster Download

```bash
nu sync_files/cluster2windows.nu \
  <ssh_host> <remote_directory> <local_directory> \
  [prefix] [suffix] [--run]
```

The optional prefix and suffix form the flat file filter `prefix*suffix`.
Omitting both transfers all files selected by rsync.

```bash
# Preview bz*.sdf download
nu sync_files/cluster2windows.nu \
  hfcluster /remote/results /mnt/d/results bz .sdf

# Perform the download
nu sync_files/cluster2windows.nu \
  hfcluster /remote/results /mnt/d/results bz .sdf --run
```

### Protected Cleanup

```bash
./clean_files/clean_files <target_directory> [--run]
```

Preview mode lists only explicit cache/editor junk and empty directories. It
protects credentials, backup data, source, PIC inputs, templates, papers,
configuration, archives, and common research-data formats. Real deletion
requires both `--run` and an exact `DELETE` confirmation.

### PIC Environment And Program Images

Environment targets are `epoch`, `smilei`, and `smilei_spin`:

```bash
# Preview
nu build_singularity_image/bd_pic_envs.nu smilei --dry-run

# Real build: no --dry-run flag
nu build_singularity_image/bd_pic_envs.nu smilei
```

Program targets are `epoch1d`, `epoch2d`, `epoch3d`, `smilei`, and
`smilei_spin`:

```bash
# Preview
nu build_singularity_image/bd_pic_images.nu epoch2d --dry-run

# Real build: no --dry-run flag
nu build_singularity_image/bd_pic_images.nu epoch2d
```

Build scripts package local source into a temporary directory, render a matching
`*.def.tmpl`, and build the configured SIF with `--force`. Source paths, image
paths, HDF5 settings, job counts, compilers, and executable names are explicit
in the build scripts.

### PIC Smoke Tests

```bash
# Preview every configured test
nu build_singularity_image/test_pic_images.nu all --dry-run

# Run one real test: no --dry-run flag
nu build_singularity_image/test_pic_images.nu smilei_spin
```

The smoke inputs under `build_singularity_image/pic_test_inputs/` check startup,
input parsing, executable linkage, MPI/HDF5 availability, and a short time loop.
Successful smoke-test working directories are reported and removed. A failed
test directory is reported and retained because its outputs may help diagnose
the failure.

### PIC Runs

Each runner accepts one input and an optional positive MPI process count. It
copies the input into a timestamped `Results_*` directory created below the
current directory, then runs the configured Apptainer image there.

```bash
# EPOCH
./run_pic/epoch1d_run.sh /path/to/input.deck [mpi_procs]
./run_pic/epoch2d_run.sh /path/to/input.deck [mpi_procs]
./run_pic/epoch3d_run.sh /path/to/input.deck [mpi_procs]

# Smilei
./run_pic/smilei_run.sh /path/to/namelist.py [mpi_procs]
./run_pic/smilei_spin_run.sh /path/to/namelist.py [mpi_procs]
```

### ASR, Translation, And Subtitle Burn-In

The Nushell pipeline runs faster-whisper transcription, optional offline NLLB
translation, and optional FFmpeg burn-in:

```bash
# Transcription only
nu asr_mt_scripts/asr_mt.nu /path/to/video.mp4 --vad

# Transcribe, translate English to Simplified Chinese, and burn subtitles
nu asr_mt_scripts/asr_mt.nu /path/to/video.mp4 \
  --vad --translate --src-lang eng_Latn --tgt-lang zho_Hans --burn
```

Generated SRT and video files are written next to the input media. The configured
container paths are under `~/Code_Program/asr_mt_containers`.

### Account Helpers

Both helpers are real-only workflows:

```bash
# Copy newest matching cluster keys to fixed WSL and Windows targets
nu transfer_cluster_key/tsf_clst_key.nu

# Initialize/sync a local folder to YuhanJin-USTC/<folder>.git
nu git_update/git_update.nu /path/to/folder "Commit message"
```

Review the source paths, destination paths, Git account, and resulting changes
before running either command.

## Repository Layout

```text
.
├── AGENTS.md                    # Coding-agent operating instructions
├── README.md                    # Human-facing guide
├── asr_mt_scripts/              # Whisper, NLLB, and FFmpeg pipeline
├── backup_archlinux/            # Backup/restore scripts and protected payloads
├── build_singularity_image/     # PIC templates, builders, and smoke inputs
├── clean_files/                 # Safe-by-default cleanup and launcher
├── git_update/                  # Real-only GitHub sync helper
├── run_pic/                     # EPOCH/Smilei Apptainer runners
├── sync_files/                  # NAS/cluster rsync scripts and rule files
├── transfer_cluster_key/        # Real-only SSH key deployment
├── update_iwan_routes/          # Panabit iWAN route preview/update
└── update_archlinux/            # Dry-run-first Arch/AUR updates
```

## Configuration Points

| Area | Edit here |
| --- | --- |
| iWAN managed host names | Top of `update_iwan_routes.ps1` |
| NAS sources and destinations | Top of `sync_files/sync_files.nu` |
| NAS exclusions | `sync_files/exclude_rules_nas_only` |
| Cluster aliases and roots | Top of `sync_files/windows2cluster.nu` |
| Cluster upload exclusions | `sync_files/exclude_rules_cluster_upload` |
| SSH key source, names, destinations | `transfer_cluster_key/tsf_clst_key.nu` |
| GitHub account and remote naming | `git_update/git_update.nu` |
| PIC source, image, build, HDF5, jobs | `bd_pic_envs.nu`, `bd_pic_images.nu` |
| PIC runtime image and executable | Matching script under `run_pic/` |
| ASR/MT image paths and defaults | `asr_mt_scripts/asr_mt.nu` |

## Validation

Use the narrowest syntax check for an edited file:

```bash
nu --ide-check 100 path/to/script.nu
bash -n path/to/script.sh
python -m py_compile path/to/script.py

ps1_path=$(wslpath -w path/to/script.ps1)
powershell.exe -NoProfile -Command \
  "\$p='$ps1_path'; \$tokens=\$null; \$errors=\$null; [void][System.Management.Automation.Language.Parser]::ParseFile(\$p,[ref]\$tokens,[ref]\$errors); if(\$errors.Count){\$errors; exit 1}"
```

For sync, transfer, update, cleanup, and container changes, inspect help and
command previews before any real execution. Do not use a real iWAN write,
backup, restore, key transfer, Git push, package update, container build, or
simulation run as a validation step.

## Coding-Agent Guidance

Repository-wide instructions for coding agents live in [`AGENTS.md`](AGENTS.md).
They define common safety, code conventions, Worklog gating, validation, and
completion criteria. The operational subtrees with distinct risk or behavior
contracts carry a local `AGENTS.md`; those files inherit the root and contain
only subsystem differences. The plural filename follows the
[open AGENTS.md convention](https://agents.md/).
