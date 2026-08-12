# Cluster Key Transfer Instructions

## Scope

These rules apply only under `transfer/` and supplement the repository-root
instructions. Changes confined here use `root:scripts/transfer` as their V0
event owner.

## Credential Invariants

- `tsf_clst_key.nu` is a real-only credential deployment workflow. It selects
  the newest source matching each configured prefix and force-copies it to
  fixed WSL and Windows SSH targets.
- Preserve explicit source prefixes, destination names, fixed target
  directories, and restrictive WSL permissions unless the user changes the
  account workflow.
- Treat a platform-specific permission operation that cannot apply as an
  explicit `[WARN]` or `[SKIP]`; do not silently swallow it.
- Do not execute the script for validation. Do not list matching key files,
  read key contents, copy keys, create SSH directories, or expose key material
  without explicit authorization.

## Validation

- Run `nu --ide-check 100 tsf_clst_key.nu`.
- Review matching, newest-file selection, destination construction, overwrite
  behavior, permissions, error propagation, and output redaction statically.
- There is no safe runtime dry run.

<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
