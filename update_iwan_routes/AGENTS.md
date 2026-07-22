# iWAN Route Instructions

## Scope

These rules apply only under `update_iwan_routes/` and supplement the
repository-root instructions. Changes confined here use
`root:scripts:update_iwan_routes` as their V0 event owner.

## Route Invariants

- Preserve preview-by-default behavior. Only `--run` may change Panabit iWAN
  configuration or managed-state files.
- Resolve only IPv4 `A` records from the DNS answer section and represent
  managed addresses as `/32` routes.
- Replace only routes previously owned by this workflow. Preserve unrelated
  custom routes, route order stability where possible, DNS, MTU,
  authentication, and every other Panabit setting.
- Require custom-route mode and the expected Panabit iWAN 2.1.3 routing
  structure. Fail closed if the structure is absent or ambiguous.
- Refuse writes while `mobile_client` is running. Keep route-only backups and
  managed state below the current Windows user's `%LOCALAPPDATA%`; never remove
  backups automatically.
- Preserve UTF-8-no-BOM writes, atomic replacement, post-write verification,
  and rollback behavior. A failure must not silently leave a partial route
  update.
- Keep the Bash wrapper limited to path conversion and PowerShell dispatch.

## Validation

- Run `bash -n update_iwan_routes`.
- Parse `update_iwan_routes.ps1` with the Windows PowerShell parser when
  available; parsing must not execute the script.
- Review managed-route diff, deduplication, write guard, backup, replacement,
  verification, and rollback paths statically.
- Help is safe after argument inspection. The default preview reads live
  Windows configuration and performs DNS queries, so run it only when that
  external access is explicitly in scope. Never use `--run` for validation.

<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
