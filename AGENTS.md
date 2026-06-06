# AGENTS.md

## Mission

This repository is `~/scripts`, a personal research-efficiency toolkit for `yuhanjin`.

The user is a laser-plasma physics researcher focused on theory, simulation, and practical tooling. Work here should make daily research tasks faster, safer, and easier to repeat.

Primary domains:

- WSL and Arch Linux maintenance
- Windows, NAS, and cluster file movement
- backup, restore, and local automation
- SSH key and account workflow scripts
- ASR/MT helper scripts
- PIC and related simulation tooling, including Smilei, EPOCH, WarpX, FaTiDo, Geant4, and containerized build/test flows

## Core Principle

Everything in this repository exists to save research time.

- Prefer practical changes that improve theory work, PIC simulation, data movement, backup/restore, container builds, or local automation.
- Keep scripts simple, editable, and easy to run by hand.
- Preserve user-editable paths, target names, image names, job counts, cluster names, and command parameters near the top when possible.
- Protect research data, credentials, backups, simulation outputs, and reproducibility over cosmetic cleanup.
- Avoid abstract refactors, new frameworks, or clever indirection unless they clearly improve daily research use.

## Hard Safety Rules

These rules override normal cleanup or refactor instincts.

- Never delete, remove, trash, prune, clean up, or overwrite user content without explicit confirmation.
- Before any deletion, state the exact target path, why deletion is needed, and wait for approval.
- Do not modify archives, encrypted data, SSH keys, GPG data, package lists, backup payloads, or research data unless explicitly requested.
- Do not modify payloads under `backup_archlinux/data` unless explicitly requested.
- Require explicit approval before editing or running workflows involving `rm`, `rm -rf`, `git reset --hard`, `git clean`, `rsync --delete`, `scp`, `sudo`, `gpg`, `pacman`, `yay`, restore operations, SSH key copying, forced Git sync, broad overwrite behavior, or real container builds.
- Do not run real restore, backup, SSH key transfer, package update, Git push, or container build commands just to validate code.
- Prefer dry runs, command previews, path inspection, syntax checks, and narrow validation before real sync, transfer, backup, restore, update, container, or deletion operations.
- Do not run `git add`, `git commit`, `git status`, or other git workflow commands unless the user explicitly asks for git-related work.

## User Identity And Stable Paths

Preserve these values unless the user explicitly changes them:

- `yuhanjin`
- `YuhanJin-USTC`
- `17865`
- `ac58qn21ek`
- `金虞焓`
- `ustcpan`
- `hfcluster`
- `tycluster`
- `wzcluster`

Treat only explicit legacy names such as `xuanwu`, `xuan_wu`, `xuan-wu`, or `xuan wu` as inherited personal information to replace.

Common paths to preserve unless instructed otherwise:

- `/home/yuhanjin`
- `/mnt/c`
- `/mnt/d`
- `/mnt/y`
- `/mnt/z/金虞焓`
- Windows user paths under `/mnt/c/Users/17865`

## Working Style

- Read nearby code before editing. Match the existing script style, command style, naming, and comments.
- Keep changes small, direct, and useful for research work.
- Preserve current script interfaces and directory layout unless the task requires changing them.
- Prefer flat scripts, explicit records, direct command construction, and step-by-step pipelines.
- Use compact English comments only when they help. Avoid long narration, decorative banners, and unrelated refactors.
- Do not rewrite working scripts just for style.
- Prefer clear variables and simple control flow over abstractions.
- When adding Nushell paths, prefer `path expand` and `path join`.
- Preserve shebangs such as `#!/usr/bin/env nu` and `#!/bin/bash`.
- For Bash scripts, preserve `set -e` unless the task is error handling.
- For Python scripts, avoid new package/framework structure unless needed.

## CLI Behavior

Repository scripts should be cautious by default.

- Prefer dry-run defaults for scripts that sync, clean, update, transfer, build, or otherwise change external state.
- Use `--run` for real execution where the script already follows that convention.
- Keep terminal output concise and consistent:
  - short colored title when useful
  - `Target`, `Mode`, and `Rule` fields for action scripts
  - status tags such as `[DRY-RUN]`, `[OK]`, `[SKIP]`, and `[ERROR]`
  - practical command previews before real external operations
- Keep logs and status output useful for later review.

Current convention examples:

- `clean_file/clean_files.nu <target_dir>` lists junk only; `--run` deletes after explicit `DELETE`.
- `sync_file/sync_files.nu <target|all>` previews rsync by default; `--run` performs sync.
- `update_archlinux/update.sh` previews package updates by default; `--run` performs updates.

## Validation

Use the narrowest useful check for changed files:

- Nushell: `nu --ide-check 100 <file>`
- Bash: `bash -n <file>`
- Python: `python -m py_compile <file>`

For behavior changes:

- Validate command construction before running real external operations.
- For sync/transfer/update/cleanup scripts, prefer dry-run or help output unless the user explicitly requests real execution.
- For container scripts, run `--dry-run` first. Run real `apptainer`/`singularity` commands only after confirming the target and intent.

## Search And Editing

- Use `rg` or `rg --files` for search.
- Use `apply_patch` for manual edits.
- Do not rewrite generated data, package lists, encrypted backups, key material, or research outputs unless explicitly requested.
- Do not use destructive filesystem commands without explicit approval.

## PIC And Container Scripts

For PIC container work, optimize for easy local modification by the user.

- Put user-editable values near the top of the total script: source paths, output paths, image names, template names, jobs, HDF5 version, compiler, and executable names.
- Keep target configuration explicit, especially EPOCH, Smilei, and Smilei-Spin records.
- Do not hide common research paths or target-specific settings behind clever generators if direct records are easier to edit.
- Use `.def.tmpl` files as stable templates. Render real `.def` files only into temporary build directories.
- Do not keep stale static `.def` files beside `.def.tmpl` templates if they are no longer used; explain the exact paths and ask before deleting.
- Default program and environment image builds may use `apptainer/singularity build --force` when the user has requested overwrite behavior. Do not manually `rm` existing images unless explicitly approved.
- Keep source tarballs and rendered def files in a temporary directory, not in source or program directories.
- For EPOCH, Smilei, and Smilei-Spin smoke tests, use small inputs that verify startup, input parsing, executable linkage, MPI/HDF5 availability, and short time-loop completion.
- For Smilei-Spin tests, include a minimal spin-specific input when possible, such as `spin_initialization` and `polarization`, to verify the spin branch is usable.

## Script Map

Use this map to orient before editing. Keep it compact; it is an agent guide, not a full README.

- `backup_archlinux/backup.sh`: backs up Arch WSL package lists, credential archive, system config, default shell, and key Git repo checks. Uses `set -e`, explicit paths, `pacman`, `tar`, `gpg`, and Git checks.
- `backup_archlinux/restore.sh`: restores a fresh Arch WSL setup. It is a root Bash pipeline that restores configs, installs packages, creates the user, decrypts credentials, installs AUR packages, force-syncs dotfiles/scripts, stows configs, and restores the default shell.
- `update_archlinux/update.sh`: dry-run-first Arch/AUR update helper. Real update mode is behind `--run`.
- `sync_file/sync_files.nu`: dry-run-first NAS sync helper. Selects a sync target by folder name or `all`; real rsync is behind `--run`.
- `sync_file/cluster2windows.nu`: downloads selected cluster files into a flat local destination using `rsync`, include filters, and SSH keepalive options.
- `transfer_cluster_key/tsf_clst_key.nu`: copies latest downloaded SSH keys into WSL and Windows `.ssh`. Uses prefix-to-target mapping, latest-file selection, `cp -f`, and chmod.
- `git_update/git_update.nu`: syncs one local folder to GitHub. It can initialize a repo, run `git add .`, commit, rename the branch to `main`, and push. Treat as high-risk until explicitly requested.
- `clean_file/clean_files.nu`: cautious junk cleanup helper. Lists protected-aware candidates by default; deletion requires `--run` and explicit `DELETE`.
- `build_singularity_image/bd_pic_envs.nu`: builds PIC environment SIF images from explicit target records and `.def.tmpl` templates.
- `build_singularity_image/bd_pic_images.nu`: builds EPOCH/Smilei program SIF images from local source using temp tarballs and rendered defs.
- `build_singularity_image/test_pic_images.nu`: runs dry-run-first smoke tests for PIC images using temp run dirs and bind mount to `/work`.
- `build_singularity_image/pic_build_common.nu`: shared Apptainer/Singularity helpers for engine selection, path checks, template rendering, placeholder validation, and temp cleanup.
- `asr_mt_scripts/asr_mt.nu`: video subtitle workflow for Whisper transcription, optional NLLB translation, and optional FFmpeg subtitle burn using Singularity containers.
- `asr_mt_scripts/transcribe.py`: Whisper SRT generation using `faster_whisper`, CUDA, timestamp formatting, and UTF-8 output.
- `asr_mt_scripts/translate.py`: NLLB SRT translation using local offline model loading, CUDA float16 inference, `pysrt`, and per-segment translation.
