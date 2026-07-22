# Sync and Transfer Instructions

## Scope

These rules apply only under `sync_files/` and supplement the repository-root
instructions. This subsystem owns NAS synchronization and cluster upload or
download. Changes confined here use `root:scripts:sync_files` as their V0 event
owner.

## Behavior Invariants

- `sync_files.nu`, `windows2cluster.nu`, and `cluster2windows.nu` remain
  preview-by-default; only `--run` performs a transfer.
- Preserve the persistent NAS history at `~/.cache/sync_files.log`. Do not
  truncate, rotate, or remove it automatically.
- Do not add `rsync --delete`, broad overwrite behavior, or implicit transfer
  targets without an explicit request and a clear warning.
- Preserve trailing-slash semantics: the configured commands transfer directory
  contents rather than nesting the source directory.
- Keep NAS mounts, local roots, cluster aliases, remote roots, SSH keepalive
  settings, include/exclude selection, and destination guards explicit.
- Treat `exclude_rules_nas_only` and `exclude_rules_cluster_upload` as public
  behavior. Inspect the applicable rule file whenever transfer selection
  changes; `--all-files` must remain an explicit bypass for cluster upload.
- Keep upload source validation and unsafe-remote-directory rejection. Preserve
  `--update`, and do not weaken the distinction between relative paths below a
  configured cluster root and explicit absolute remote paths.
- A real Data download or synchronization must be explicitly requested. Record
  its defined scope, command result, and integrity or completeness evidence in
  the initiating writable work unit; never infer `synced` from path or file
  existence and never write workflow records into Data.

## Validation

- Run `nu --ide-check 100` on every changed Nushell file when Nushell is
  available.
- Review both transfer endpoints, constructed `ssh`/`rsync` arguments, rule-file
  selection, and dry-run branching statically.
- Use only agent-created temporary directories for rule fixtures. Do not use a
  mounted drive, NAS path, cluster directory, or research case as test data.
- Do not connect to a cluster or NAS for routine validation. Even dry-run rsync
  may read external state and requires an explicitly scoped task.

<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
