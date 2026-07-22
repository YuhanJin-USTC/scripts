# Git Update Instructions

## Scope

These rules apply only under `git_update/` and supplement the repository-root
instructions. Changes confined here use `root:scripts:git_update` as their V0
event owner.

## Git Invariants

- `git_update.nu` is a real-only Git and network workflow. It may initialize a
  repository, verify a remote, add `origin`, stage all files, commit, rename the
  branch to `main`, and push.
- Never run it unless the user explicitly requests Git publication for the
  exact target directory and accepts the resulting local and remote changes.
- Preserve the explicit GitHub account, folder-derived repository name,
  optional commit message, clean-tree handling, and visible remote target
  unless the interface is intentionally changed.
- Do not use this helper, or separate Git commands, as validation for an edit in
  this repository. Do not create a remote repository automatically.

## Validation

- Run `nu --ide-check 100 git_update.nu` when Nushell is available.
- Review path validation, remote construction, mutation order, error handling,
  and push behavior statically. There is no safe runtime dry run.

<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
