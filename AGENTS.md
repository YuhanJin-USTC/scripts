# AGENTS.md

## Project Context

This repository is `~/scripts`, a personal research-efficiency toolkit for `yuhanjin`.

The user is a laser-plasma physics researcher focused on theory, simulation, and practical tooling. Work in this repository should directly improve research efficiency.

Typical workflows involve PIC codes and related simulation/tooling programs, including Smilei, EPOCH, WarpX, FaTiDo, Geant4, Singularity/Apptainer, cluster file transfer, backup/restore, and local automation.

## Hard Safety Rules

- Never delete, remove, trash, prune, clean up, or overwrite files in a way that removes user content without explicit confirmation.
- Before any deletion, state the exact target path, why deletion is needed, and wait for approval.
- Do not modify archives, encrypted data, SSH keys, GPG data, or backup payloads under `backup_archlinux/data` unless explicitly requested.
- Be careful with scripts that run `rm`, `rsync --delete`, `sudo`, `scp`, `gpg`, restore operations, `git add .`, or `git push`.
- Prefer dry runs, command inspection, or narrow validation before real sync, transfer, backup, restore, or deletion operations.

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
- Preserve current script interfaces and directory layout unless the task requires changing them.
- Match the existing simple script style.
- Use compact English comments only when they help.
- Avoid long explanatory comments, decorative section banners, and unrelated refactors.
- Do not rewrite working scripts just for style.
- Prefer clear variables and simple control flow over abstractions.
- When adding Nushell paths, prefer `path expand` and `path join`.
- Keep personal configuration explicit when that matches the existing script.

## Singularity/Apptainer PIC Scripts

For PIC container work, optimize for easy local modification by the user.

- Put user-editable values near the top of the total script: source paths, output paths, image names, template names, jobs, HDF5 version, compiler, and executable names.
- Keep target configuration explicit. Do not hide common research paths or target-specific settings behind clever generators if direct records are easier to edit.
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
