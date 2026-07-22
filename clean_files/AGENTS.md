# Cleanup Instructions

## Scope

These rules apply only under `clean_files/` and supplement the repository-root
instructions. Changes confined here use `root:scripts:clean_files` as their V0
event owner.

## Behavior Invariants

- Default mode only enumerates candidates. Real deletion requires both
  `--run` and the exact typed confirmation `DELETE`.
- Preserve protected path parts, protected extensions, broad-target guards,
  no-symlink traversal, explicit junk rules, and the ordering that removes
  deeper directories before parents.
- A file with no extension remains protected. Source, scripts, PIC inputs,
  templates, papers, configuration, archives, backups, credentials, and common
  research-data formats must not become cleanup candidates accidentally.
- Any change to candidate or protection rules requires focused cases made only
  from task-created temporary files. Never test deletion against user data.

## Validation

- Run `bash -n clean_files` and `nu --ide-check 100 clean_files.nu` when the
  tools are available.
- For rule changes, verify preview output first with a dedicated temporary
  fixture. Do not exercise `--run` unless the user explicitly requests that
  exact deletion test and approves its exact temporary paths.

<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
