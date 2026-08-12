# Update Workflow Instructions

## Scope

These rules apply only under `update/` and supplement the repository-root
instructions. Changes confined here use `root:scripts/update` as their V0
event owner.

## Arch Linux

- `update_archlinux.sh` remains preview-by-default. Only `--run` may update
  the keyring, official packages, or AUR packages.
- Preserve the non-root guard for real mode and the separation between preview
  queries and real package operations.
- Do not run package queries or updates merely to validate an edit.

## iWAN Routes

- `update_iwan_routes.sh` remains a thin WSL-to-PowerShell wrapper.
  `update_iwan_routes.ps1` remains preview-by-default.
- Resolve only IPv4 A records from DNS answer sections and represent managed
  addresses as `/32` routes.
- Replace only workflow-owned routes. Preserve unrelated routes, order where
  practical, DNS, MTU, authentication, and all other Panabit settings.
- Require custom-route mode and a stopped `mobile_client` before writes.
  Preserve route-only backups, UTF-8-no-BOM atomic replacement, verification,
  and rollback.
- Preview reads live Windows configuration and DNS; it requires explicit scope.

## GitHub Update

- `update_git.nu` is real-only. It may initialize a repository, verify a
  remote, add `origin`, stage all files, commit, rename the branch to `main`,
  and push.
- Never run it unless the user requests Git publication for the exact target
  and accepts the local and remote mutations.
- Preserve the configured account, folder-derived repository name, optional
  message, clean-tree handling, and visible remote target.
- Do not create a remote repository automatically.

## Validation

- Run `bash -n update_archlinux.sh` and `bash -n update_iwan_routes.sh`.
- Run `nu --ide-check 100 update_git.nu`.
- Parse the PowerShell source without executing it.
- Review argument handling, mode guards, route ownership/rollback, Git mutation
  order, and external exit propagation statically.
- Never run package, DNS, iWAN, Git, or network operations for validation.

<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
