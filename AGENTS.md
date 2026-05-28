# AGENTS.md

## Project Context

This repository is `~/scripts`, a personal research-efficiency toolkit for `yuhanjin`.

The user is a laser-plasma physics researcher focused on theory, simulation, and practical tooling. Work in this repository should directly improve research efficiency.

Typical workflows involve WSL, Arch Linux, Windows paths, NAS sync, cluster transfer, backup/restore, SSH keys, local automation, ASR/MT tooling, and PIC codes such as Smilei, EPOCH, WarpX, FaTiDo, and Geant4.

## Core Principle

Everything in this repository exists to save research time.

- Prefer changes that make theory work, PIC simulation, data movement, backup/restore, container builds, or local automation faster, safer, or easier to repeat.
- Avoid abstract refactors, new frameworks, or clever indirection unless they clearly improve daily research use.
- Preserve simple, editable workflow scripts. The user should be able to change paths, targets, image names, cluster names, and commands quickly.
- Protect research data, credentials, backups, simulation outputs, and reproducibility over cosmetic cleanup.

## Hard Safety Rules

- Never delete, remove, trash, prune, clean up, or overwrite files in a way that removes user content without explicit confirmation.
- Before any deletion, state the exact target path, why deletion is needed, and wait for approval.
- Do not modify archives, encrypted data, SSH keys, GPG data, or backup payloads under `backup_archlinux/data` unless explicitly requested.
- Do not modify package lists, backup payloads, encrypted archives, SSH/GPG data, or research data unless explicitly requested.
- Require explicit approval before editing or running workflows involving `rm`, `rm -rf`, `git reset --hard`, `git clean`, `rsync --delete`, `scp`, `sudo`, `gpg`, `pacman`, `yay`, restore operations, SSH key copying, forced Git sync, or broad overwrite behavior.
- Be careful with scripts that run `rsync`, `cp -f`, `git add .`, `git push`, `stow`, `tar`, container builds, or Windows/WSL path writes.
- Prefer dry runs, command previews, path inspection, or narrow validation before real sync, transfer, backup, restore, update, container, or deletion operations.
- Do not run real restore, backup, SSH key transfer, package update, Git push, or container build commands just to validate code. Validate syntax or dry-run output unless the user explicitly asks for the real operation.

## User Identity And Paths

These values belong to the user and should be preserved unless explicitly changed by the user:

- `yuhanjin`
- `YuhanJin-USTC`
- `17865`
- `ac58qn21ek`
- `金虞焓`
- `ustcpan`
- `hfcluster`
- `tycluster`
- `wzcluster`

Only explicit legacy names such as `xuanwu`, `xuan_wu`, `xuan-wu`, or `xuan wu` should be treated as inherited personal information to replace.

## Code Style

- Keep changes small, direct, and useful for research work.
- Learn the existing style before editing. Inspect nearby scripts and match their structure, command style, naming, and comments.
- Preserve current script interfaces and directory layout unless the task requires changing them.
- Match the existing simple script style.
- Use compact English comments only when they help. Prefer short phrases like the existing scripts; avoid long narration.
- Avoid long explanatory comments, decorative section banners, and unrelated refactors.
- Do not rewrite working scripts just for style.
- Prefer clear variables and simple control flow over abstractions.
- Keep user-editable paths, names, targets, image names, job counts, and command parameters near the top when possible.
- Preserve flat scripts, direct command construction, explicit records, and step-by-step pipelines.
- When adding Nushell paths, prefer `path expand` and `path join`.
- Keep personal configuration explicit when that matches the existing script.

## WSL Workflow Conventions

- Preserve WSL, Windows, NAS, and cluster paths unless the user explicitly changes them: `/home/yuhanjin`, `/mnt/c`, `/mnt/d`, `/mnt/y`, `/mnt/z/金虞焓`, and similar paths.
- Preserve explicit user and account identifiers from `User Identity And Paths`.
- Keep dry-run modes as defaults where they already exist.
- Keep logs, status output, and command previews practical and concise.
- Do not replace practical workflow scripts with package-style framework structure.

## Script Map

Use this map to understand the workflow before editing. Keep this section compact; it is an agent guide, not a full README.

- `backup_archlinux/backup.sh`: backs up Arch WSL package lists, a credential archive, system config, default shell, and checks key Git repos. It is a step-by-step Bash pipeline with `set -e`, explicit paths, `pacman`, `tar`, `gpg`, and Git status checks.
- `backup_archlinux/restore.sh`: restores a fresh Arch WSL setup. It is a root Bash pipeline that restores configs, installs packages, creates the user, decrypts credentials, installs AUR packages, force-syncs dotfiles/scripts, stows configs, and restores the default shell.
- `update_archlinux/update.sh`: dry-run-first Arch/AUR update helper. It uses Bash option parsing, `checkupdates`/`pacman -Qu`, `yay -Qua`, and real update mode behind `--run`.
- `sync_file/sync_files.nu`: syncs WSL research and work directories to NAS. It uses Nushell config records, `rsync` argument construction, logging, path checks, exclude rules, and `--dry-run`.
- `sync_file/cluster2windows.nu`: downloads selected cluster files into a flat local destination. It wraps `rsync` with optional prefix/suffix include filters and SSH keepalive options.
- `transfer_cluster_key/tsf_clst_key.nu`: copies latest downloaded SSH keys into WSL and Windows `.ssh`. It uses a prefix-to-target map, latest-file selection, `cp -f`, and chmod.
- `git_update/git_update.nu`: syncs one local folder to GitHub. It checks remote existence, optionally initializes a repo, runs `git add .`, commits, renames the branch to `main`, and pushes.
- `clean_file/clean_files.nu`: cautious junk cleanup helper. It uses protected path and extension rules, dry-run listing by default, and explicit `DELETE` confirmation before removal.
- `build_singularity_image/bd_pic_envs.nu`: builds PIC environment SIF images. It uses explicit target records, `.def.tmpl` rendering into temp dirs, engine auto-selection, and `build --force`.
- `build_singularity_image/bd_pic_images.nu`: builds EPOCH/Smilei program SIF images from local source. It uses explicit per-target config, a temp source tarball, a rendered def, an environment image, and `build --force`.
- `build_singularity_image/test_pic_images.nu`: runs smoke tests for PIC images. It uses explicit image/input/command records, temp run dirs, bind mount to `/work`, and `--dry-run`.
- `build_singularity_image/pic_build_common.nu`: shared helpers for Apptainer/Singularity selection, path checks, template rendering, placeholder validation, and temp cleanup.
- `asr_mt_scripts/asr_mt.nu`: video subtitle workflow. It is a Nushell pipeline for Whisper transcription, optional NLLB translation, and optional FFmpeg subtitle burn using Singularity containers.
- `asr_mt_scripts/transcribe.py`: Whisper SRT generation. It uses `faster_whisper`, CUDA, timestamp formatting, and UTF-8 SRT output.
- `asr_mt_scripts/translate.py`: NLLB SRT translation. It uses local offline model loading, CUDA float16 inference, `pysrt`, and per-segment translation.

## Singularity/Apptainer PIC Scripts

For PIC container work, optimize for easy local modification by the user.

- Put user-editable values near the top of the total script: source paths, output paths, image names, template names, jobs, HDF5 version, compiler, and executable names.
- Keep target configuration explicit, especially EPOCH, Smilei, and Smilei-Spin records. Do not hide common research paths or target-specific settings behind clever generators if direct records are easier to edit.
- Keep common fields common, but do not add unused empty parameters just to make records look identical.
- Use `.def.tmpl` files as stable templates. Render real `.def` files only into temporary build directories.
- Do not keep stale static `.def` files beside `.def.tmpl` templates if they are no longer used; explain the exact paths and ask before deleting.
- Default program and environment image builds may use `apptainer/singularity build --force` when the user has requested overwrite behavior. Do not manually `rm` existing images unless explicitly approved.
- Keep source tarballs and rendered def files in a temporary directory, not in source or program directories.
- For EPOCH, Smilei, and Smilei-Spin smoke tests, use small inputs that only verify startup, input parsing, compiled executable linkage, MPI/HDF5 availability, and short time-loop completion.
- For Smilei-Spin tests, include a minimal spin-specific input when possible, such as `spin_initialization` and `polarization`, to verify the spin branch is actually usable.

## Repo Conventions

- Use `rg` or `rg --files` for search.
- Use `apply_patch` for manual edits.
- Do not rewrite generated data, package lists, encrypted backups, or key material unless explicitly requested.
- Preserve shebangs such as `#!/usr/bin/env nu`.
- For Python scripts, avoid new framework structure unless needed.
- For Bash scripts, preserve `set -e` behavior unless the task is error handling.

## Validation

Use the narrowest useful check for changed files:

- Nushell: `nu --ide-check 100 <file>`
- Python: `python -m py_compile <file>`
- Bash: `bash -n <file>`

For behavior changes, validate command construction before running real external operations.
For container scripts, run `--dry-run` first. Run real `apptainer exec` or `apptainer build` only when needed and after confirming the command target.
