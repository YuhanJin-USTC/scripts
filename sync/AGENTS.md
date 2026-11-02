# Sync and Transfer Instructions

## Scope

These rules apply only under `sync/` and supplement the repository-root
instructions. This domain owns NAS synchronization and cluster upload or
download. Changes confined here use `root:scripts/sync` as their V0 event
owner.

## Behavior Invariants

- `sync_files.nu`, `windows2cluster.nu`, and `cluster2windows.nu` remain
  preview-by-default. Only `--run` performs a transfer.
- Preserve the persistent NAS history at `~/.cache/sync_files.log`. Do not
  truncate, rotate, or remove it automatically.
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
  that status without an extra confirmation gate. Run explicitly uses SSH typed
  inventories before/after transfer; payloads remain on Rayfile. Never infer
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
<!-- digest: 89d09a6994f49df8c13b524a2af6ad0acf361194fc848c001cb517be1ee3a44f -->
## Managed Research Workflow Policy

- `case-confirmation`: "A Case target does not imply a Case edit. For explicit registration or simulation-definition changes, finish files/checks, show the saved preview, actually ask and await the user, then apply the exact plan. A digest is not consent; unchanged accepted definitions add no revision."
- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, build, or Git mutations without explicit user authorization."
- `framework-authority`: "Use Research Workflow 0.2.4 and the unversioned researchctl CLI. Preserve journal-only Case authority, original Event fields, historical migrate/tombstone bindings, immutable streams, and fail-closed forks."
- `indexing`: "Treat SQLite and saved plans as device-local derived state. Queries may refresh the disposable index; never synchronize it or use it as authority."
- `multi-device`: "Synchronize and check portable authority before context or any portable write after switching devices, including event-only work. Keep local TOML/device/paths, upgrade devices sequentially, and stop old metadata writers until local acceptance. External sync remains separately authorized."
- `propagation`: "Preview pending policy semantics, exact targets and differences; obtain real user approval of the stable digest, record it through policy approve, then apply. Preserve cumulative device approvals and unmanaged AGENTS bytes; Data/Notes and body patches require exact separate scope."
- `recording`: "Restore bounded Case, Study, Project, or exact root/path memory. Record one substantive result as an event at the most specific owner; retain purpose, result, accepted reasons, validation level and limits in existing summary/evidence. Do not log ordinary Q&A or create empty membership or pending queues."
- `workspace-routing`: "Resolve local access through verified roots and explicit mappings. Logical memory may be queried without a local mapping, but new writes require local registration. Keep Data read-only and Notes access within exact authorized links/sections."

<!-- research-workflow:policy:end -->
