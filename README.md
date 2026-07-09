# scripts

Personal research-efficiency scripts for Arch Linux on WSL, Windows/NAS file
movement, cluster transfers, PIC container workflows, and ASR/MT helpers.

The repository is intentionally flat and script-first. Most values that change
often, such as paths, image names, cluster aliases, and job counts, live near the
top of each script.

## Safety Model

Scripts that can change external state are cautious where practical.

- `sync_files/sync_files.nu`, `sync_files/cluster2windows.nu`,
  `sync_files/windows2cluster.nu`, `clean_files/clean_files.nu`, and
  `update_archlinux/update.sh` default to preview or dry-run behavior.
- Real sync, transfer, cleanup, or update actions require `--run` where the
  script supports it.
- Restore, backup, Git sync, SSH key copy, and container build scripts should be
  read carefully before running because they intentionally perform real system,
  credential, Git, or image operations.

## Common Commands

```bash
# Arch/AUR update preview
./update_archlinux/update.sh

# NAS sync preview
nu sync_files/sync_files.nu all

# Cluster upload preview
nu sync_files/windows2cluster.nu hfcluster /path/to/case Simulation/case

# Cluster download preview
nu sync_files/cluster2windows.nu hfcluster /remote/path /local/path bz .sdf

# Junk cleanup preview
nu clean_files/clean_files.nu /path/to/project

# PIC image build preview
nu build_singularity_image/bd_pic_images.nu smilei --dry-run

# PIC image smoke-test preview
nu build_singularity_image/test_pic_images.nu all --dry-run
```

## Script Map

### Arch Linux WSL

- `update_archlinux/update.sh` previews and runs official repo plus AUR updates.
- `backup_archlinux/backup.sh` records package lists, archives selected system
  and home configuration, archives sensitive credentials with GPG, and checks
  important Git repositories.
- `backup_archlinux/restore.sh` restores a fresh Arch WSL setup from the backup
  payloads and remote Git repositories. Run only after reviewing the script.

### File Sync And Transfer

- `sync_files/sync_files.nu` syncs selected local folders to NAS locations using
  rsync and `sync_files/exclude_rules_nas_only`.
- `sync_files/windows2cluster.nu` uploads a local simulation case directory to a
  configured cluster target. It uses `sync_files/exclude_rules_cluster_upload`
  unless `--all-files` is used.
- `sync_files/cluster2windows.nu` downloads selected remote files into a flat
  local destination using optional prefix/suffix filters.
- `clean_files/clean_files.nu` lists safe junk candidates by default and deletes
  only after `--run` plus an explicit `DELETE` confirmation.

### PIC Containers And Runs

- `build_singularity_image/bd_pic_envs.nu` builds environment images for EPOCH,
  Smilei, and Smilei-Spin from `.def.tmpl` templates.
- `build_singularity_image/bd_pic_images.nu` builds runnable PIC program images
  from local source trees and environment images.
- `build_singularity_image/test_pic_images.nu` runs dry-run-first smoke tests
  against the built program images.
- `run_pic/*.sh` runs EPOCH or Smilei inputs in the corresponding Apptainer
  image and writes results into timestamped `Results_*` directories.

### ASR And Translation

- `asr_mt_scripts/asr_mt.nu` runs the video subtitle pipeline:
  Whisper transcription, optional NLLB translation, and optional FFmpeg subtitle
  burn-in.
- `asr_mt_scripts/transcribe.py` is the container-side faster-whisper helper.
- `asr_mt_scripts/translate.py` is the container-side NLLB SRT translation
  helper.

### Account Helpers

- `transfer_cluster_key/tsf_clst_key.nu` copies the newest downloaded cluster
  SSH keys into WSL and Windows `.ssh` targets.
- `git_update/git_update.nu` initializes or syncs a local directory to a GitHub
  repository with the same folder name. It stages, commits, and pushes when
  changes exist.

## Validation

Use the narrowest syntax check for edited scripts:

```bash
nu --ide-check 100 path/to/script.nu
bash -n path/to/script.sh
python -m py_compile path/to/script.py
```

For sync, transfer, update, cleanup, and container workflows, validate with
`--help`, dry-run output, or command previews before running real operations.
