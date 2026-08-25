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
<!-- digest: 495b19a971d7b9b9af14663fdb4e74e31ef626d7e19a9c856f7fa4b1b28f080e -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, build, or Git mutations without explicit user authorization."
- `framework-authority`: "Use Research Workflow 0.2.2 journal-only Case authority and the unversioned researchctl CLI; historical migrate and migrate-tombstone records remain readable, schema-1 per-Case files and migration commands are unsupported, every multi-device Case write must match the latest synchronized journal head digest, and external synchronization requires explicit user authorization."
- `indexing`: "Treat .research-workflow/index.sqlite3 as local, derived, rebuildable cache only; it is never portable authority."
- `propagation`: "Use exact allowlisted targets, explicit scope approval, and a digest-bound policy apply while preserving unmanaged AGENTS bytes."
- `recording`: "Restore compact context first and record one risk-tiered checkpoint at the most specific owner; unsupported scientific status remains unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through exact knowledge links or explicit user requests."

<!-- research-workflow:policy:end -->
