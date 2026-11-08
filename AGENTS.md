# scripts Agent Instructions

## Scope

Read this file, the owning subsystem rules, README, implementation and callers. Keep this toolkit script-first, with public usage in README and local exceptions in the owning AGENTS.md. PIC and post-processing share build_containers/AGENTS.md. Do not add parallel instructions, frameworks, dependency layers or a host Python environment merely to reorganize scripts.

For a change to core logic, name the script and entry point, current and proposed behavior and affected callers, data and outputs. Obtain explicit approval covering that change. One specific approval suffices. A general optimization request grants no core change.

## Common Safety

- Protect research data, inputs/outputs, sources, backups, archives, encrypted files, package lists, configs, backup/archlinux/data, GPG and keys. Get exact approval before deleting, moving, replacing or overwriting user content. Keep secrets out of commands, logs, metadata and replies.
- Classify each command as read, preview or write. Require explicit scope for state changes, privilege, credentials, remote work and all Git, including status/add/commit. This includes rm, rm -rf, git reset --hard, git clean, rsync --delete, scp, sudo, gpg, pacman, yay, restore, SSH-key copying, forced sync and broad overwrites.
- Never run transfers, cleanup, updates, backup/restore, key deployment, iWAN writes, builds, smoke tests, PIC or media generation merely to validate code. Inspect help/preview branches for external reads. Use only approved temporary fixtures, never research trees, mounts, NAS, cluster paths, backups or user media.
- Remove only exact task-owned temporary artifacts with CODEX_TEMP_CLEANUP=1. Preserve required failure evidence.

## Procedure

Trace arguments, outputs, absolute paths, external commands and cross-root writes. Preserve public flags, defaults, output locations, shell and layout. Reread changed files directly. Keep code, help, README and templates consistent. For durable interface, ownership, safety or validation changes, show the owning AGENTS.md diff for approval.

Preserve established identifiers and paths unless the user changes them,
including `yuhanjin`, `YuhanJin-USTC`, `17865`, `ac58qn21ek`, `金虞焓`,
`ustcpan`, `hfcluster`, `tycluster`, `wzcluster`, `/home/yuhanjin`, `/mnt/c`,
`/mnt/d`, `/mnt/y`, `/mnt/z/金虞焓`, and Windows paths below
`/mnt/c/Users/17865`. Treat only explicit `xuanwu`, `xuan_wu`, `xuan-wu`, or
`xuan wu` occurrences as legacy identity text to replace.

## Common Style

- Match local organization, naming, diagnostics and short English comments. Use domain directories and full snake_case verb-object names for new entries. Preserve README compatibility names (bd_*, tsf_clst_key, windows2cluster, cluster2windows) and scientific tokens (epoch1d, epoch2d, epoch3d, smilei_spin).
- Keep editable paths, targets, images, jobs and parameters explicit near use. Resolve sibling assets from the script. Preserve intentional external research, image, mount, Windows and cluster paths.
- Preserve intentional absolute paths and shebangs. Avoid unrelated formatting.
- Use the output order title, `Target`, `Mode`, `Rule`, then workflow-specific
  fields. Use `[DRY-RUN]` for preview guarantees, `[n/N]` for a stage that is
  starting, `[OK]` only after success, `[SKIP]` for an intentional omission,
  `[WARN]` for a recoverable problem, and `[ERROR]` for a fatal failure.
- Send fatal diagnostics to stderr and exit nonzero. Do not swallow a failed
  external command, print a normal stack trace for a user error, or report a
  final `[OK]` after a partial failure.
- Keep help safe and side-effect free. Present usage, one-line purpose,
  arguments, options, and useful examples; parse help and invalid arguments
  before dependency checks or external reads. Preserve each workflow's
  established preview-by-default, real-by-default, or real-only mode.
- Keep concise warnings for overwrite, deletion, remote paths, trailing slashes, credentials, rollback and reproducibility. Explicit changes to public flags or modes require updated help, examples, README and approved rule changes.

### Bash

- Preserve the existing strict-mode choice; use `set -Eeuo pipefail` for a new
  operational script when appropriate, but do not retrofit it blindly.
- Use two-space indentation, `snake_case` functions and locals, and
  `UPPER_SNAKE_CASE` user configuration. Preserve intentional shebangs.
- Quote path and user-derived values. Prefer arrays for constructed commands,
  keep preflight and execution blocks easy to scan, and do not introduce
  `eval`.

### Nushell

- Preserve `#!/usr/bin/env nu`, typed `main` parameters, and useful `--help`
  output.
- Use `kebab-case` commands and helper functions, and `snake_case` variables and
  record fields. Keep user-facing flags in `--kebab-case`.
- Prefer lists with argument spreading, `path expand`, and `path join`.
  Preserve deliberate remote path strings and handle external exit status when
  it affects correctness.
- Use `error make` for fatal local validation and an explicit captured result
  or exit-code check for external commands. Do not mix a printed `[ERROR]` with
  a successful return path.

### Python

- Use argparse, explicit UTF-8, snake_case, UPPER_SNAKE_CASE constants, lightweight annotations, main() and raise SystemExit(main()). Keep heavyweight model/CUDA assumptions visible. Send progress/errors to stderr when stdout is machine-readable. Container helpers need no host package or manifest unless requested.

### PowerShell

- Preserve strict mode, stop-on-error behavior, `Verb-Noun` functions,
  PascalCase parameters, camelCase locals, `-LiteralPath`, UTF-8-no-BOM writes,
  atomic replacement, and rollback guards.
- Keep persisted JSON field names unchanged when they form an external schema.
  Use the shared header, field, and status conventions instead of scattered
  `Write-Host` diagnostics.

## Research ownership

Use `python3 -B /home/yuhanjin/Research_Workflow/tools/researchctl.py context "root:scripts/<exact-directory>" --view compact --json`, or root:scripts for repository-wide work. Recurse only for a requested subtree. Checkpoint one durable result at its most specific owner. For joint work, list the affected paths at one primary owner. Keep history in the control repo. Retirement requires an approved same-root ancestor plan. Body edits and deletion need separate approval.
## Validation

Use the narrowest applicable baseline:

| Artifact | Baseline check | Safe follow-up |
| --- | --- | --- |
| `*.nu` | `nu --ide-check 100 <file>` | inspected `--help` or documented preview |
| `*.sh` or Bash wrapper | `bash -n <file>` | inspected `--help` |
| `*.ps1` | Windows PowerShell parser | inspected help or preview |
| `*.py` | `python3 -B -c 'import pathlib; p=pathlib.Path("<file>"); compile(p.read_text(encoding="utf-8"), str(p), "exec")'` | inspected `--help`; do not load models |
| `*.def.tmpl` | placeholder and renderer review | build-script dry run only when authorized |
| PIC test input | static parser/input review | existing harness dry run only when authorized |
| exclude or cleanup rule | rule and command-construction review | agent-created temporary fixture |
| Markdown | headings, links, paths, commands, and scope review | none |

Additional requirements:

- A preview may read local or remote state. Do not run it unless its behavior is
  understood and the required paths, mounts, network access, and task scope are
  authorized.
- If an alternative Python validator creates `__pycache__`, remove only the
  cache created by the current validation with the required temporary-cleanup
  marker.
- If an executable or external path is unavailable, report the skipped check.
  Do not install dependencies, fabricate paths, or weaken a guard.

Report changed paths, completed and skipped checks, and unresolved unknown or to-confirm items. Verify public behavior, task outputs and cleanup before handoff.
<!-- research-workflow:policy:start -->
<!-- digest: 255425630765de0b777c8b315a1469fc936fca419187535850dcd16888fc5f5d -->
## Managed Research Workflow Policy

- `case-confirmation`: "Case ownership alone changes no definition. For registration, definition or lifecycle changes, finish files/checks, show the saved plan, ask and await consent, then apply its digest. Equal definitions add no revision."
- `external-operations`: "Require explicit task authorization for Git, network/API, SSH, cluster, transfer, sync, simulation, MATLAB, builds, containers and SIF operations."
- `framework-authority`: "Use Research Workflow 0.2.4 and its unversioned CLI. Preserve journal-only Cases, original Event fields, migrate/tombstone bindings and immutable streams. Stop on forks."
- `indexing`: "SQLite and saved plans are disposable device-local state. Queries may refresh SQLite. Never sync either or use it as authority."
- `multi-device`: "After a switch, preserve local work and separately authorize sync. Check portable authority with doctor, event merge and validate before context or any portable write. Keep TOML, paths and identity local. Upgrade sequentially with old writers stopped through acceptance."
- `propagation`: "Show pending semantics, exact targets, diffs and stable digest. After user approval, record it with policy approve and apply that digest. Preserve cumulative approvals and unmanaged bytes. Data, Notes and body patches need separate exact scope."
- `recording`: "Restore compact Case, Study, Project or exact root/path context. Record one substantive result at its closest eligible owner, with purpose, result, accepted reasons, checks and limits in summary/evidence. Skip ordinary discussion, empty membership and pending queues."
- `workspace-routing`: "Use verified roots and explicit mappings. Unmapped logical memory is readable. Local access and new writes need registration. Data stays read-only. Scope Notes to exact links/sections and writes to explicit requests."

<!-- research-workflow:policy:end -->
