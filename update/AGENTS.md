# Update Workflow Instructions

## Arch Linux and Editor Updates

- `update_archlinux.sh` remains preview-by-default. Only `--run` may mutate
  packages or prepare an editor generation; never run it merely for validation.
- Default scope has two stages: complete the system update, then prepare and
  validate an isolated Neovim candidate. Preserve `--system-only` and
  `--editor-only`; failed package queries must fail visibly.
- Keep the non-root guard and one complete `pacman -Syu --needed archlinux-keyring`
  transaction before AUR updates; do not introduce a standalone `-Sy`. Treat
  reported ALPM hook errors as failures even with exit zero, and retain logs.
  Editor failure does not roll back packages or switch the active generation.
- Standalone update prepares and validates a candidate, then prints the activation command. Separate activation/rollback require --run and the reviewed --expect-identity. Retain failed and previous generations. A requested real restore may activate a validated generation within its restore transaction.
- `nvim_state.py` is the sole public editor lifecycle; `mason_tools.py` is an
  internal backend. Preserve the complete original parser coverage plus latex
  (23 parsers), explicit shared specs and fresh real validation under the lock.
- Keep Jukit on the system Python/IPython and the four selected Arch packages.
  Pinned reconstruction of the original Mason tools is separately authorized;
  never install external tools implicitly during startup or candidate validation.

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

- `update_git.nu` is real-only. It may initialize a repository on `main`, verify
  a remote, add `origin`, stage all files, commit and push `main`.
- Never run it unless the user requests Git publication for the exact target
  and accepts the local and remote mutations.
- Use an existing `origin` before deriving a repository from the directory
  name. Preserve the configured account as the no-origin fallback, optional
  message, clean-tree handling and visible remote target.
- Refuse existing non-main branches and detached HEAD before network access or
  mutation. Never rename an existing branch. Feature work uses reviewed PRs,
  not this direct-main publication helper.
- Do not create a remote repository automatically.

## Validation

- Run `bash -n update_archlinux.sh` and `bash -n update_iwan_routes.sh`.
- Run `nu --ide-check 100 update_git.nu`.
- Check origin selection, branch guards and failure propagation with a fake
  Git executable in owned temporary fixtures; never publish for validation.
- Parse the PowerShell source without executing it.
- Review argument handling, mode guards, route ownership/rollback, Git mutation
  order, and external exit propagation statically.
- Never run package, DNS, iWAN, Git, or network operations for validation.

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
