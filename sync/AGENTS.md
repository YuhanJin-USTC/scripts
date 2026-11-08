# Sync and Transfer Instructions

## Behavior Invariants

- `sync_files.nu`, `windows2cluster.nu`, and `cluster2windows.nu` remain
  preview-by-default. Only `--run` performs a transfer.
- NAS preview checks mounts, runs rsync --dry-run and appends to ~/.cache/sync_files.log. Preserve this history in both modes. Never truncate, rotate or remove it automatically.
- Do not add `rsync --delete`, broad overwrite behavior, or implicit transfer
  targets without explicit authorization and a clear warning.
- Preserve trailing-slash semantics: configured commands transfer directory
  contents rather than nesting the source directory.
- Keep mounts, local roots, cluster aliases, remote roots, SSH keepalive
  settings, include/exclude rules, and destination guards explicit.
- Treat both `exclude_rules_*` files as public behavior.
  `--all-files` must remain an explicit cluster-upload bypass.
- Keep upload source validation, unsafe-remote-directory rejection, and
  `--update`. Reject conflicting mode flags and propagate external SSH/rsync
  failures as nonzero exits.
- A real Data download or synchronization requires an explicit request. Record
  completeness evidence in the initiating writable work unit, never in Data.

## Fast Transfer

- Preserve `fclst2win`, `fwin2clst` and the existing terminal-output conventions.
  Register only hf/hfcluster at `/public/home/yuhanjin` and ty/tycluster,
  wz/wzcluster at `/work/home/yuhanjin`, each with portal home `/`.
- For fast download, map only the selected registered SSH home plus its exact
  `/` boundary to the portal home; relative paths use that home. Other absolute
  paths retain portal meaning. `--portal-path` bypasses SSH-home conversion.
  Never guess a mapping for an unknown target or a merely similar prefix.
- `clst2win` expands relative paths only for the registered clusters. Preserve
  absolute SSH paths and all other SSH hosts' existing pass-through behavior.
  Keep SSH and portal namespaces explicit in preview output.
- Default fast preview is local-only: no token, client, connection or destination
  creation. Preserve exclusive `--dry-run`, `--list`, `--attributes`, `--ssh-list`, `--run`;
  `--portal-path` is a namespace option, not an execution mode.
- `--list` and `--attributes` are separately authorized exact-path metadata
  probes through the restricted native client. Neither downloads, recursively
  probes, applies prefix/suffix filtering to its output, or uses the local
  destination. Attributes does not establish a complete directory listing.
- Support hf/ty/wz downloads through the same runtime checks. Only WZ has live
  fixture acceptance; HF/TY remain untested against their servers and display
  that status without an extra confirmation gate. Run both typed inventories
  on one SSH session and fail closed on disconnect. Keep the device and inode
  checks and bounded source-difference diagnostics. Payloads use Rayfile. Never infer
  reliable types from native list/attributes or widen incomplete selections.
- Absolute UTF-8 filelists flatten basenames. Batch by parent into separate
  empty stages, reconstruct inner paths, and verify exact files/types/sizes
  plus unchanged SSH stat metadata before publishing. No per-file probing,
  rsync payload fallback or implicit all-files transfer.
- Stage on the destination filesystem. Publish with no-overwrite hard links;
  number incoming collisions as `name.1.ext`. Preserve existing content and
  fail clearly if hard links are unsupported. Report partial local publication
  and retain bounded credential-free failure diagnostics while cleaning owned
  stage payloads. Native failures must publish nothing.
- Keep the 45-second/1-MiB bounds for metadata only. Production transfer has
  no total time limit, retains bounded logs in memory, and terminates its child
  process group on interruption. Do not treat `Failed: 0` as failure or claim
  production remote hash verification from the synthetic fixture hashes.
- Prefix/suffix selection follows rsync filename-byte globs `*`, `?`, balanced
  `[]` and directory blocking. Refuse `/`, backslash, `**`, controls and invalid
  classes; reject links, unknown types, duplicates and absent parent records.
- Reject the resolved portal root, dot segments and unsafe local destinations.
  Preserve quoted path whitespace and Unicode spelling. Remove the source root
  only once and preserve internal paths; retain the reviewed rename contract.
  Unsupported download exclusions must refuse, never silently widen selection.
- Upload keeps native rename semantics, existing exclusions and `--all-files`.
  Merge wildcard patterns into one semicolon-separated `-exd`; repeated `-exd`
  replaces prior patterns. Do not apply download assumptions to upload.
- Runtime hidden prompts and `RAYFILE_TOKEN` are sensitive. Never persist tokens,
  reuse samples or print them in previews/diagnostics. Keep probe runtime state
  ephemeral, response/time bounds and terminal restoration. A source mapping
  or one server observation does not verify other servers or real transfers.

## Validation

- Run `nu --ide-check 100` on each changed Nushell file.
- Review endpoints, SSH/rsync arguments, rule selection, and preview branching
  statically.
- Use only task-created temporary directories for rule fixtures.
- Do not connect to a cluster or NAS for routine validation. Even an rsync dry
  run may read external state and requires an explicitly scoped task.
- Validate fast-transfer argument construction, redaction, preview side effects
  and failure propagation with temporary local fixtures. Native option checks
  must be isolated from external networks and real credentials. Keep real-server
  filtering, naming and transfer-success claims unverified until tested.

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
