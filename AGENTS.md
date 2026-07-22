# scripts Agent Instructions

## Scope and Authority

These instructions apply to the repository rooted at `/home/yuhanjin/scripts`.
Read the nearest nested `AGENTS.md` before working in a subsystem; nested files
contain only subtree-specific rules and inherit this file. Explicit user
instructions take priority within the authorized scope.

`README.md` is the human-facing behavior and usage guide. Keep durable agent
rules here and subsystem differences in the owning nested `AGENTS.md`. Do not
create parallel instruction files such as `AGENT.md`, `CLAUDE.md`, or
tool-specific rule files unless the user requests them.

This is a personal, script-first research toolkit. Prefer direct changes that
reduce friction in laser-plasma research, PIC simulation, data movement, system
maintenance, and local automation. Do not add a framework, package hierarchy,
task runner, generated configuration layer, or host Python environment merely
to make the repository resemble an application project.

## Common Safety

- Do not delete, move, replace, clean, prune, or overwrite user content without
  explicit approval for the exact paths. Protect research data, inputs,
  outputs, source, credentials, backups, archives, encrypted files, package
  lists, and configuration.
- Do not modify `backup_archlinux/data`, key material, GPG data, or other
  protected payloads unless the user explicitly includes them.
- Classify commands before execution as read-only, preview, or state-changing.
  State-changing work requires explicit user intent; destructive, privileged,
  credential, broad-overwrite, or remote operations also require confirmation
  immediately before execution when it is not already explicit.
- Require explicit approval before invoking workflows involving `rm`,
  `rm -rf`, `git reset --hard`, `git clean`, `rsync --delete`, `scp`, `sudo`,
  `gpg`, `pacman`, `yay`, restore, SSH-key copying, forced Git synchronization,
  or broad overwrite behavior. The exact task-created temporary cleanup allowed
  below is the only standing exception.
- Never run synchronization, transfer, cleanup, package update, backup,
  restore, key deployment, iWAN write, Git mutation, container build or smoke
  test, PIC run, or media-generation workflow merely to validate a change.
- Do not run Git commands, including `git status`, `git add`, or `git commit`,
  unless the user explicitly requests Git work.
- Prefer source inspection, syntax checks, command construction review, and a
  documented non-mutating preview. Inspect argument handling before assuming
  that `--help` or a dry run is safe.
- Never use a research directory, source tree, mounted drive, NAS path,
  cluster path, backup location, or user media as disposable test data.
- Remove only temporary artifacts created by the current task. Mark the exact
  cleanup command with `CODEX_TEMP_CLEANUP=1`; preserve failed diagnostic
  artifacts when the owning subsystem requires them.
- Keep credentials, private keys, tokens, passphrases, and sensitive payload
  content out of commands, logs, metadata, and responses.

## Common Work Procedure

1. Read this file, the nearest nested `AGENTS.md`, the relevant `README.md`
   sections, and every affected script, template, rule file, and caller.
2. Trace arguments, intentional absolute paths, generated files, overwrite or
   deletion behavior, external commands, and cross-project writes end to end.
3. Confirm the authorized target and preserve unrelated user changes. Treat
   each registered research root as a separate write scope.
4. Make the smallest coherent change. Preserve public flags, defaults, output
   locations, shell choice, and directory layout unless the task changes them.
5. Run the narrowest safe validation. Do not turn validation into a real
   external operation.
6. Re-read every changed file directly; do not use Git to review changes unless
   Git work was requested.
7. Update `README.md` and the applicable `AGENTS.md` when interfaces,
   dependencies, paths, safety behavior, validation, or layout change.

Preserve established identifiers and paths unless the user changes them,
including `yuhanjin`, `YuhanJin-USTC`, `17865`, `ac58qn21ek`, `金虞焓`,
`ustcpan`, `hfcluster`, `tycluster`, `wzcluster`, `/home/yuhanjin`, `/mnt/c`,
`/mnt/d`, `/mnt/y`, `/mnt/z/金虞焓`, and Windows paths below
`/mnt/c/Users/17865`. Treat only explicit `xuanwu`, `xuan_wu`, `xuan-wu`, or
`xuan wu` occurrences as legacy identity text to replace.

## Common Style

- Match nearby organization, naming, command construction, diagnostics, and
  comment density. Keep comments short and in English; do not narrate obvious
  code.
- Keep user-editable paths, target records, image names, job counts, and common
  parameters explicit and near the top when practical.
- Preserve intentional absolute paths and shebangs. Do not rewrite working code
  solely for style or perform repository-wide formatting.
- Keep command output concise. Preserve established `Target`, `Mode`, and
  `Rule` fields and status tags such as `[DRY-RUN]`, `[OK]`, `[SKIP]`, and
  `[ERROR]` where the script already uses them.
- Do not silently invert an execution default or rename a public flag. If a
  mode changes, update help text, examples, `README.md`, and all affected rules
  in the same task.

### Bash

- Preserve the existing strict-mode choice; use `set -Eeuo pipefail` for a new
  operational script when appropriate, but do not retrofit it blindly.
- Quote path and user-derived values. Prefer arrays for constructed commands,
  keep preflight and execution blocks easy to scan, and do not introduce
  `eval`.

### Nushell

- Preserve `#!/usr/bin/env nu`, typed `main` parameters, and useful `--help`
  output.
- Prefer lists with argument spreading, `path expand`, and `path join`.
  Preserve deliberate remote path strings and handle external exit status when
  it affects correctness.

### Python

- Keep helpers focused with `argparse` entry points and explicit UTF-8 text
  handling. Keep heavyweight model or CUDA assumptions visible near use.
- Do not add a host dependency manifest or package structure for code intended
  to run inside a container unless requested.

## Research Workflow Contract

- Before a substantive task, run
  `python3 -B /home/yuhanjin/Research_Workflow/tools/researchctl.py context "<target>" --recent 3 --json`
  and read the bounded V0 root context.
- Do not create Cards or Worklogs or reconstruct history. On the first
  substantive modification, reusable validation result, or explicit decision
  owned by a subsystem, preview `researchctl.py event record` for that exact
  owner, inspect the canonical V0 event, and repeat the same identity and times
  with `--write`. Refuse the append when no device ID is configured.
- Record an event once at the most specific owner. A repository-wide agent or
  documentation standardization event belongs at the repository root rather
  than being copied into every subsystem. A cross-root atomic task has one
  primary owner and lists every affected path.
- Keep `.research-workflow/index.sqlite3` local-only and never create it as a
  side effect of context restoration or recording.
- Do not log pure Q&A, planning, read-only inspection, or an unsuccessful task
  with no durable result. Use concise English and exclude secrets, raw output,
  full conversations, and unsupported conclusions.

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

## Completion

A task is complete only when:

- the requested behavior or documentation is implemented without unrelated
  refactoring;
- user content, protected data, credentials, and unrelated edits remain
  untouched;
- public interfaces and intentional paths are preserved unless explicitly
  changed;
- applicable safe checks pass, or every skipped check is explained;
- no real external-state workflow was run merely for validation;
- task-created temporary artifacts are removed under the cleanup contract;
- code, help, `README.md`, templates, rules, and agent instructions agree; and
- the handoff lists changed paths, validation, skipped operations, and all
  remaining `unknown` or `to-confirm` items.
<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
