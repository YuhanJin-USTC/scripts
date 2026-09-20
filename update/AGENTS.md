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
<!-- digest: 53b828bcd3473143cd53c8eb3790393d6fec47f065abe2b14e0e167f32b593b7 -->
## Managed Research Workflow Policy

- `case-confirmation`: "A Case target does not imply a Case edit. For explicit registration or simulation-definition changes, finish files/checks, show the saved preview, actually ask and await the user, then apply the exact plan. A digest is not consent; unchanged accepted definitions add no revision."
- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, build, or Git mutations without explicit user authorization."
- `framework-authority`: "Use Research Workflow 0.2.3 and the unversioned researchctl CLI. Preserve journal-only Case authority, original Event fields, historical migrate/tombstone bindings, immutable streams, and fail-closed forks."
- `indexing`: "Treat SQLite and saved plans as device-local derived state. Queries may refresh the disposable index; never synchronize it or use it as authority."
- `multi-device`: "Synchronize and check portable authority before context or any portable write after switching devices, including event-only work. Keep local TOML/device/paths, upgrade devices sequentially, and stop old metadata writers until local acceptance. External sync remains separately authorized."
- `propagation`: "Preview pending policy semantics, exact targets and differences; obtain real user approval of the stable digest, record it through policy approve, then apply. Preserve cumulative device approvals and unmanaged AGENTS bytes; Data/Notes and body patches require exact separate scope."
- `recording`: "Restore bounded Case, Study, Project, or exact root/path memory. Record one substantive result as an event at the most specific owner; retain purpose, result, accepted reasons, validation level and limits in existing summary/evidence. Do not log ordinary Q&A or create empty membership or pending queues."
- `workspace-routing`: "Resolve local access through verified roots and explicit mappings. Logical memory may be queried without a local mapping, but new writes require local registration. Keep Data read-only and Notes access within exact authorized links/sections."

<!-- research-workflow:policy:end -->
