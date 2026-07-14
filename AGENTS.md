# Repository Instructions for Coding Agents

## Scope And Precedence

- This file applies to the entire repository rooted at `~/scripts`.
- A nested `AGENTS.md`, if added later, overrides this file only for files in
  that subtree.
- Direct user instructions override repository defaults. Safety requirements
  still apply unless the user explicitly authorizes the relevant operation.
- `README.md` is the human-facing usage guide. Keep implementation rules and
  agent constraints here; keep user commands and workflow explanations there.
- Do not create parallel agent instruction files such as `AGENT.md`,
  `CLAUDE.md`, or tool-specific rule files unless the user requests them.

## Project Overview

This repository is `~/scripts`, a personal research-efficiency toolkit for
`yuhanjin`.

The user is a laser-plasma physics researcher focused on theory, simulation,
and practical tooling. Work here should make daily research tasks faster,
safer, and easier to repeat.

Primary domains:

- WSL and Arch Linux maintenance
- Windows Panabit iWAN route maintenance
- Windows, NAS, and cluster file movement
- backup, restore, and local automation
- SSH key and account workflow scripts
- ASR/MT helper scripts
- PIC and related simulation tooling, including Smilei, EPOCH, WarpX, FaTiDo,
  Geant4, and containerized build/test flows

Project characteristics:

- Personal, single-user toolkit rather than a distributable package.
- Script-first layout with no repository-wide build system or test runner.
- Bash, Nushell, Python, Apptainer/Singularity definition templates, and small
  PIC smoke-test inputs.
- WSL and Arch Linux assumptions, with intentional absolute paths for the
  owner's Windows mounts, NAS mounts, clusters, source trees, and images.
- External-state workflows are common, so validation must be narrower and more
  cautious than ordinary application development.

## Core Principle

Everything in this repository exists to save research time.

- Prefer practical changes that improve theory work, PIC simulation, data
  movement, backup/restore, container builds, or local automation.
- Keep scripts simple, editable, and easy to run by hand.
- Preserve user-editable paths, target names, image names, job counts, cluster
  names, and command parameters near the top when possible.
- Protect research data, credentials, backups, simulation outputs, and
  reproducibility over cosmetic cleanup.
- Avoid abstract refactors, new frameworks, or clever indirection unless they
  clearly improve daily research use.

## Repository Layout

| Path | Purpose | Risk profile |
| --- | --- | --- |
| `update_archlinux/` | Arch/AUR updates | System packages |
| `update_iwan_routes/` | Panabit iWAN cluster-route update | Windows app config |
| `backup_archlinux/` | Backup and restore | System, secrets |
| `sync_files/` | NAS and cluster transfer | External writes |
| `transfer_cluster_key/` | SSH key deployment | Secret overwrite |
| `git_update/` | Commit and push | Git/remote state |
| `clean_files/` | Protected-aware junk discovery and cleanup | File deletion |
| `build_singularity_image/` | PIC build and test | SIF, sudo |
| `run_pic/` | PIC container runners | Compute/results |
| `asr_mt_scripts/` | GPU ASR/MT pipeline | Media writes |
| `README.md` | Human usage guide | Documentation |
| `AGENTS.md` | Repository-wide agent instructions | Agent behavior |

Do not introduce a package hierarchy, framework, task runner, or generated
configuration layer merely to make this small script repository resemble an
application project.

## Environment And Dependencies

- Primary environment: Arch Linux under WSL, with Windows paths mounted under
  `/mnt/c` and `/mnt/d` and NAS paths under `/mnt/y` and `/mnt/z`.
- Shells: Bash and Nushell. Preserve the shell already used by each script.
- Common tools: `rsync`, OpenSSH, Git, `tar`, `gpg`, and standard Linux tools.
- iWAN route workflow: WSL, `wslpath`, Windows PowerShell, and Panabit iWAN
  2.1.3 under the current Windows user.
- Arch workflows: `pacman`, `yay`, and optionally `checkupdates` from
  `pacman-contrib`.
- PIC workflows: `apptainer` or `singularity`; run scripts currently require
  the `apptainer` command specifically.
- ASR/MT workflow: `singularity`, NVIDIA GPU access in WSL, prebuilt local
  containers, and `ffmpeg` when burning subtitles.
- Python dependencies for ASR/MT live inside their containers. Do not add a
  host Python environment or dependency manifest unless requested.
- There is no repository-wide install, build, lint, or test command. Validate
  only the files and workflows affected by the change.

## Hard Safety Rules

These rules override normal cleanup or refactor instincts.

- Never delete, remove, trash, prune, clean up, or overwrite user content
  without explicit confirmation.
- Before any deletion, state the exact target path, why deletion is needed, and
  wait for approval.
- Do not modify archives, encrypted data, SSH keys, GPG data, package lists,
  backup payloads, or research data unless explicitly requested.
- Do not modify payloads under `backup_archlinux/data` unless explicitly
  requested.
- Require explicit approval before editing or running workflows involving
  `rm`, `rm -rf`, `git reset --hard`, `git clean`, `rsync --delete`, `scp`,
  `sudo`, `gpg`, `pacman`, `yay`, restore operations, SSH key copying, forced
  Git sync, broad overwrite behavior, or real container builds.
- Do not run real restore, backup, SSH key transfer, package update, Git push,
  iWAN route write, or container build commands just to validate code.
- Prefer dry runs, command previews, path inspection, syntax checks, and narrow
  validation before real sync, transfer, backup, restore, update, container,
  or deletion operations.
- Do not run `git add`, `git commit`, `git status`, or other Git workflow
  commands unless the user explicitly asks for Git-related work.
- Read-only inspection, `--help`, syntax checks, and dry runs that are proven not
  to alter external state are the default validation tools.
- If the agent creates temporary validation artifacts, remove only those
  artifacts when finished. Prefix the cleanup command with
  `CODEX_TEMP_CLEANUP=1` and name the exact temporary path.
- Never use a real research directory, source tree, mounted drive, NAS target,
  cluster path, or backup location as disposable test data.

### Risk Classification

Classify a command before running it:

1. **Read only:** path inspection, file reads, searches, syntax checks, and help
   output. Safe by default.
2. **Preview:** a documented dry run that does not create, overwrite, transfer,
   install, or delete data. Preferred for behavior checks.
3. **State changing:** sync, transfer, package operations, backup, restore,
   credential handling, Git mutation, media output, simulation runs, image
   builds, or cleanup. Requires explicit user intent; high-risk operations also
   require confirmation immediately before execution.

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

Treat only explicit legacy names such as `xuanwu`, `xuan_wu`, `xuan-wu`, or
`xuan wu` as inherited personal information to replace.

Common paths to preserve unless instructed otherwise:

- `/home/yuhanjin`
- `/mnt/c`
- `/mnt/d`
- `/mnt/y`
- `/mnt/z/金虞焓`
- Windows user paths under `/mnt/c/Users/17865`

## Required Agent Workflow

1. Read this file and the relevant portions of `README.md`.
2. Use `rg` or `rg --files` to locate the affected scripts, templates, rules,
   and test inputs.
3. Read nearby code before editing. Trace arguments, absolute paths, generated
   files, and external commands end to end.
4. Identify whether the requested work touches credentials, backups, research
   data, deletion, Git state, package state, transfers, containers, or compute.
5. Make the smallest coherent change. Preserve unrelated user edits and avoid
   repository-wide formatting.
6. Run the narrowest safe validation from the matrix below. Do not turn a
   validation step into a real external operation.
7. Re-read the final diff without using Git unless Git work was requested.
8. Update `README.md` and this file when interfaces, dependencies, paths,
   safety behavior, validation, or repository layout changed.
9. Report changed files, validations performed, and anything intentionally not
   executed because it needs user approval or external resources.

## General Conventions

- Read nearby code before editing. Match the existing script style, command
  style, naming, and comments.
- Keep changes small, direct, and useful for research work.
- Preserve current script interfaces and directory layout unless the task
  requires changing them.
- Prefer flat scripts, explicit records, direct command construction, and
  step-by-step pipelines.
- Use compact English comments only when they help. Avoid long narration,
  decorative banners, and unrelated refactors.
- Do not rewrite working scripts just for style.
- Prefer clear variables and simple control flow over abstractions.
- When adding Nushell paths, prefer `path expand` and `path join`.
- Preserve shebangs such as `#!/usr/bin/env nu` and `#!/bin/bash`.
- For Bash scripts, preserve `set -e` unless the task is error handling.
- For Python scripts, avoid new package/framework structure unless needed.

### Bash

- Preserve the file's existing strict-mode choice. New operational Bash scripts
  should normally use `set -Eeuo pipefail`; do not retrofit it blindly.
- Quote path and user-derived variables.
- Keep `usage`, status formatting, preflight checks, and execution blocks easy
  to scan.
- Prefer arrays for constructed commands. Do not introduce `eval`.

### Nushell

- Preserve `#!/usr/bin/env nu` for executable Nushell scripts.
- Use typed `main` parameters and flags so `--help` remains useful.
- Prefer lists and argument spreading for external commands.
- Use `path expand` and `path join`; preserve deliberate remote path strings.
- Read `$env.LAST_EXIT_CODE` or handle failures explicitly where external
  command status matters.

### Python

- Keep container-side helpers as focused scripts with `argparse` entry points.
- Use UTF-8 explicitly for subtitle or text output.
- Keep heavyweight model loading and CUDA assumptions visible near use.
- Do not add dependencies outside the owning container workflow without a
  concrete need and corresponding documentation.

### Templates And Test Inputs

- Stable container definitions use `*.def.tmpl`; rendered `*.def` files belong
  only in temporary build directories.
- Preserve placeholders in `{{NAME}}` form and keep rendering values explicit.
- Keep smoke inputs minimal, deterministic, and fast while still exercising
  input parsing, executable linkage, MPI/HDF5 startup, and a short time loop.

## CLI Behavior

Repository scripts should be cautious by default.

- Prefer dry-run defaults for scripts that sync, clean, update, transfer,
  build, or otherwise change external state.
- Use `--run` for real execution where the script already follows that
  convention.
- Keep terminal output concise and consistent:
  - short colored title when useful
  - `Target`, `Mode`, and `Rule` fields for action scripts
  - status tags such as `[DRY-RUN]`, `[OK]`, `[SKIP]`, and `[ERROR]`
  - practical command previews before real external operations
- Keep logs and status output useful for later review.

Current convention examples:

- `clean_files/clean_files.nu <target_dir>` lists junk only; `--run` deletes
  after explicit `DELETE`.
- `sync_files/sync_files.nu <target|all>` previews rsync by default; `--run`
  performs sync.
- `update_archlinux/update.sh` previews package updates by default; `--run`
  performs updates.

Current execution modes must be described accurately:

| Workflow | Default invocation | Real execution |
| --- | --- | --- |
| Arch update | Preview | `--run` |
| iWAN route update | Preview | Exit iWAN, then use `--run` |
| NAS sync | Preview | `--run` |
| Cluster upload/download | Preview | `--run` |
| Junk cleanup | Preview | `--run`, then type `DELETE` |
| PIC image build | Real build | Add `--dry-run` to preview |
| PIC smoke test | Real test | Add `--dry-run` to preview |
| Backup/restore, key/Git sync, PIC run, ASR/MT | Real | No dry run |

Do not silently invert an existing mode or rename a public flag. If safer
defaults are introduced, update the script help, examples, `README.md`, and
this table together.

## Subsystem Contracts

### Sync And Transfer

- Preserve dry-run defaults and command previews.
- Preserve the persistent NAS sync history at `~/.cache/sync_files.log`; it is
  useful for later review and must not be removed automatically.
- Do not add `--delete` or broad overwrite behavior without an explicit user
  request and a clear warning.
- Preserve rsync trailing-slash semantics: these scripts intentionally transfer
  directory contents rather than nesting the source directory.
- Keep cluster aliases, remote roots, include/exclude behavior, SSH keepalive
  settings, and destination safety guards explicit.
- Treat exclude-rule files as part of the public behavior; inspect them whenever
  transfer selection changes.

### iWAN Routes

- Preserve preview-by-default behavior; only `--run` may change Panabit
  settings.
- Resolve only IPv4 A records from the DNS answer section and use `/32` routes.
- Preserve non-managed routes and never change DNS, MTU, authentication, or
  other Panabit settings.
- Refuse writes while `mobile_client` is running or when the expected 2.1.3
  routing structure is absent.
- Keep route state and route-only backups under the current Windows user's
  `%LOCALAPPDATA%`; never remove backups automatically.
- Do not run a real route update for validation. Use help, syntax parsing, and
  the default preview against the real configuration.

### Backup, Restore, Credentials, And Git

- `backup.sh` writes package lists and archives, invokes GPG, and inspects Git.
  It is a real operation, not a harmless validation command.
- `restore.sh` is a root-only, system-changing pipeline with package installs,
  credential restore, stow operations, and forced Git synchronization. Never
  run it for testing.
- Use unique temporary restore paths and remove them with exit cleanup on both
  success and failure; do not remove timestamped safety backups automatically.
- Keep SSH key material, GPG data, encrypted archives, and app credentials out
  of logs and tool output.
- `tsf_clst_key.nu` and `git_update.nu` perform real overwrite or remote Git
  actions. Inspect or syntax-check them; do not execute them without request.

### Cleanup

- Default mode must only enumerate candidates.
- Preserve protected path parts, protected extensions, broad-target guards,
  `--run`, and the exact typed `DELETE` confirmation.
- Changes to candidate or protected rules require test cases built from
  agent-created temporary files, never user data.

### PIC Containers And Runs

- Keep environment images, program images, and runtime scripts as separate
  stages.
- Builds render definitions and source archives in temporary directories and
  may overwrite SIF images with `build --force`; never manually pre-delete SIFs.
- Report and remove temporary build directories on both success and failure.
  Remove successful smoke-test directories, but report and retain failed test
  directories because their outputs may be useful for diagnosis.
- Runners must create isolated timestamped result directories and preserve the
  input used for the run.
- Do not launch a real image build, smoke test, or simulation merely to verify a
  documentation or command-construction change.

### ASR And Translation

- Preserve the three-stage pipeline: transcription, optional translation, and
  optional subtitle burn-in.
- The Python helpers are container-side implementation details; host execution
  is not the normal workflow.
- Treat source media and generated SRT/video files as user content. Do not
  overwrite, delete, or use them as disposable validation artifacts.

## Validation

Use the narrowest applicable check:

| Changed artifact | Required baseline | Optional safe behavior check |
| --- | --- | --- |
| `*.nu` | `nu --ide-check 100 <file>` | `--help` or documented dry run |
| `*.sh` or Bash wrapper | `bash -n <file>` | `--help` or documented dry run |
| `*.ps1` | Windows PowerShell parser | `--help` or documented dry run |
| `*.py` | `python -m py_compile <file>` | `--help`; do not load models |
| `*.def.tmpl` | Inspect placeholders/renderer | Build `--dry-run` |
| PIC test input | Parser/static review | Existing test harness `--dry-run` |
| Exclude rule | Inspect rule and rsync command | Script dry run |
| Markdown | Check structure, links, paths, commands | None |

Additional rules:

- Validate command construction before running real external operations.
- For sync, transfer, update, and cleanup scripts, use help or dry-run output
  unless the user explicitly requests real execution.
- For container scripts, use `--dry-run` first. Real builds and smoke tests need
  confirmed target and intent.
- `--help` is not assumed safe automatically: inspect argument parsing first,
  especially in scripts whose dependency checks precede help handling.
- Python compilation may create `__pycache__`. Remove only the cache generated
  by the validation, using the required temporary-cleanup marker.
- If a required executable or external path is unavailable, report the skipped
  check. Do not install packages, fabricate research paths, or weaken guards.

## Search And Editing

- Use `rg` or `rg --files` for search.
- Use `apply_patch` for manual edits.
- Do not rewrite generated data, package lists, encrypted backups, key
  material, or research outputs unless explicitly requested.
- Do not use destructive filesystem commands without explicit approval.
- Do not use Git commands to discover or summarize changes unless Git-related
  work was explicitly requested. Re-read the edited files directly.

## Documentation Contract

- `README.md` must describe the repository as it currently behaves, including
  prerequisites, hard-coded environment assumptions, risk level, exact CLI
  syntax, default execution mode, configuration points, outputs, and safe
  validation.
- `AGENTS.md` must describe how agents should inspect, edit, validate, and hand
  off changes without duplicating the full user guide.
- Any public CLI, dependency, path convention, target, safety mechanism, or
  directory-layout change requires a same-task documentation update.
- Keep examples copyable from the repository root. Use placeholders such as
  `/path/to/case` only where the user must substitute a value.
- Do not claim portability that the scripts do not have. Absolute paths and WSL
  assumptions are intentional and must be called out.
- Do not add badges, support policies, contribution claims, CI status, releases,
  or licensing terms that do not exist in the repository.

## PIC-Specific Implementation Details

For PIC container work, optimize for easy local modification by the user.

- Put user-editable values near the top of the total script: source and output
  paths, image and template names, jobs, HDF5 version, compiler, and executable.
- Keep target configuration explicit, especially EPOCH, Smilei, and
  Smilei-Spin records.
- Do not hide common research paths or target settings behind generators when
  direct records are easier to edit.
- Use `.def.tmpl` files as stable templates. Render real `.def` files only into
  temporary build directories.
- Do not keep unused static `.def` files beside `.def.tmpl` templates. Explain
  the exact paths and ask before deleting.
- Image builds may use `apptainer/singularity build --force` when overwrite
  behavior was requested. Do not manually `rm` images without approval.
- Keep source tarballs and rendered def files in a temporary directory, not in
  source or program directories.
- For EPOCH, Smilei, and Smilei-Spin smoke tests, use small inputs that verify
  startup, input parsing, executable linkage, MPI/HDF5, and a short time loop.
- For Smilei-Spin, include a minimal spin input when possible, such as
  `spin_initialization` and `polarization`, to verify the branch is usable.

## Script Map

Use this map to orient before editing. Keep it compact; this is not the user
guide.

- `backup_archlinux/backup.sh`: writes package lists, credential/config archives,
  the default shell, and core Git checks.
- `backup_archlinux/restore.sh`: root pipeline for configs, packages, user,
  credentials, stow, forced repo sync, and default shell.
- `update_archlinux/update.sh`: dry-run-first Arch/AUR update; `--run` updates.
- `update_iwan_routes/update_iwan_routes`: WSL launcher for the Windows
  PowerShell iWAN route updater.
- `update_iwan_routes/update_iwan_routes.ps1`: resolves managed cluster hosts,
  previews route changes, and writes Panabit settings only with `--run`.
- `sync_files/sync_files.nu`: dry-run-first selected NAS sync; `--run` syncs.
- `sync_files/cluster2windows.nu`: dry-run-first filtered cluster download to a
  flat local destination; `--run` transfers.
- `sync_files/windows2cluster.nu`: dry-run-first upload to a preset cluster root
  or absolute remote path; `--run` transfers.
- `sync_files/exclude_rules_nas_only`: exclusion rules used by NAS sync.
- `sync_files/exclude_rules_cluster_upload`: default large-output exclusions;
  `--all-files` bypasses them.
- `transfer_cluster_key/tsf_clst_key.nu`: copies the latest matching SSH keys
  into fixed WSL and Windows targets with `cp -f`.
- `git_update/git_update.nu`: may initialize, stage, commit, rename `main`, and
  push a folder. Treat as high-risk.
- `clean_files/clean_files`: Bash launcher for the absolute-path Nushell script.
- `clean_files/clean_files.nu`: previews protected-aware junk candidates;
  deletion needs `--run` and `DELETE`.
- `build_singularity_image/bd_pic_envs.nu`: real-by-default environment SIF
  build from explicit records and templates; `--dry-run` previews.
- `build_singularity_image/bd_pic_images.nu`: real-by-default program SIF build
  from local source and rendered defs; `--dry-run` previews.
- `build_singularity_image/test_pic_images.nu`: real-by-default PIC smoke tests
  in temporary run dirs; `--dry-run` previews.
- `build_singularity_image/pic_build_common.nu`: shared engine, path, render,
  placeholder, and temporary-cleanup helpers.
- `build_singularity_image/pic_env_defs/`: stable environment-image templates.
- `build_singularity_image/pic_defs/`: stable program-image templates.
- `build_singularity_image/pic_test_inputs/`: minimal EPOCH, Smilei, and
  Smilei-Spin smoke inputs.
- `run_pic/epoch1d_run.sh`, `epoch2d_run.sh`, and `epoch3d_run.sh`: run one deck
  in the matching image, optionally with MPI, into a timestamped result dir.
- `run_pic/smilei_run.sh` and `smilei_spin_run.sh`: run one namelist in the
  matching image, optionally with MPI, into a timestamped result dir.
- `asr_mt_scripts/asr_mt.nu`: Whisper transcription, optional NLLB translation,
  and optional FFmpeg subtitle burn using Singularity.
- `asr_mt_scripts/transcribe.py`: CUDA faster-whisper to UTF-8 SRT.
- `asr_mt_scripts/translate.py`: offline CUDA NLLB translation of SRT segments.

## Completion Criteria

A task is complete only when all applicable items are true:

- The requested behavior or documentation is implemented without unrelated
  refactoring.
- User content, credentials, backups, research data, and unrelated edits remain
  untouched.
- Public interfaces and intentional absolute paths are preserved unless the
  user requested a change.
- The narrowest relevant checks pass, or skipped checks are explained.
- No real external-state workflow was run merely for validation.
- Agent-created temporary artifacts are removed safely.
- `README.md`, `AGENTS.md`, help text, templates, and rules agree with the final
  behavior.
- The handoff states what changed, what was validated, and what still requires
  explicit execution or approval.
