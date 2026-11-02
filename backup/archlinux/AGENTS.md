# Arch Backup and Restore Instructions

## Scope

These rules supplement the repository instructions under `backup/archlinux/`.
The exact result owner is `root:scripts/backup/archlinux`. Keep the two Bash
entry points and focused existing helpers; do not introduce a framework or
parallel instruction files. Usage belongs in `backup/README.md`.

## Backup contract

- `backup.sh [--preview]` is real by default. Format 2 publishes only package
  lists, selected system/home configuration, encrypted credentials and pinned
  source records, plus manifest/COMPLETE, at `data/github-current`.
- Projects/plugins/binaries are reconstructed from published sources. Verify
  local project changes and actual remote availability before publishing;
  never commit/push for the user or accept stale tracking refs as proof.
- Keep accepted runtime/plugin/parser versions, tool receipts and checksums.
  Refuse unpublished personal edits and missing exact source provenance.
  Inspect tracked plugin source changes only; never scan untracked/ignored
  plugin runtime files or require whole-installation hashes during backup.
  Select Neovim configuration from Git-tracked paths plus the active lockfile.
  Capture credentials through explicit durable-file selectors, not whole SSH/GPG
  runtime directories. Omit cache inventories and unrelated private npm records.
- Build privately and publish atomically. A failed invocation removes only its
  incomplete set and retains the last complete publication. Existing tracked
  format-1 payloads await their separately approved history/data cleanup.
- Never capture scientific data, models, images, device-local workspace.toml,
  local indexes/plans, or additional Codex personal settings/skills.

## Restore contract

- `restore.sh [--set PATH|--legacy PATH] [--keep-local-workflow] [--preview]`
  is real by default; no path selects the fixed current set. Keep format-1
  complete-set reading and legacy exit-3 incomplete reporting.
- A restore command authorizes scoped replacements, selected package operations,
  pinned reconstruction and editor activation. Do not ask per-file confirmation.
  Password input remains separate. Preview performs no decryption/network/write.
- Before destination changes, validate archives/checksums/links/space and check
  existing projects for unpublished work. Stop the entire restore on conflict.
  Never restore a scripts worktree snapshot over the executing checkout.
- Existing projects must fast-forward without losing local ignored state.
  Stage matching complete checkouts locally after publication checks. Fetch
  file contents before checkout for other pins and attribute failures to the
  active project.
  Preserve device identity/path settings. Never replace populated divergent
  Research_Workflow authority, auto-merge journals, or copy desktop identity to
  another device. New-device registration/full acceptance remains separate and
  must be reported as uncovered until completed.
- Compare encrypted effective Git/rclone content with published Stow content;
  disagreement stops preflight. `.ssh/config` remains owned by dot_files/Stow.
  Use real Stow with no-folding and journal every changed managed destination.
- Keep archive traversal, type/link, synthetic-parent and permission checks.
  Never copy staging 0700 modes onto unrelated parents or write through links.
- Keep network/build output under invocation staging. Package upgrades, new
  accounts and generated system databases are not file-rollback guarantees.
- Keep the disposable Pacman/yay package cache outside private staging. Its
  root must be owned by root and traversable by Pacman's configured DownloadUser.

## Temporary files and rollback

- `backup_set.py` owns archive checks, temporary identity checks and the file
  transaction; `rebuild_tools.py` owns source checks/downloads/build staging.
- On success discard invocation staging and temporary originals. On an ordinary
  error or catchable interruption, roll back managed files/tools/links first,
  then clean. Terminate owned build children before deleting their staging.
- Do not create home-level restore backups, persistent failure diagnostics or
  per-run arch-recovery directories. Print errors on the terminal.
- Preserve only originals whose rollback actually failed or paths whose cleanup
  identity cannot be trusted; print exact paths. Never delete prior-run data,
  historical generations, or arbitrary files by a cleanup glob.
- Keep plaintext at 0600 inside 0700 roots. Private GPG agents retain their
  socket/process ownership guards. Mark owned cleanup CODEX_TEMP_CLEANUP=1.
  SIGKILL/power loss cannot execute traps; do not promise otherwise.

## Editor and client

- `nvim_state.py` remains the editor lifecycle and `mason_tools.py` internal.
  Reuse the explicit plugin_specs inventory. Preserve 23 parser languages,
  grammar revisions, native builds and real isolated editor acceptance.
- Restore builds at pinned sources and validates before activation. Standalone
  prepare/activate/rollback retain their existing explicit lifecycle gates and
  historical generations. Invocation-created failed restore candidates are
  cleaned; existing generations are never swept.
- Jukit uses system Python/IPython with the four existing Arch dependencies;
  do not invent a host environment or restore the old ~/base path.
- Reconstruct clangd, pylsp, clang-format and stylua at their original Mason
  paths. Use the official compiler's resolved receipt source, including version
  overrides, and retain registry/source/dependency checks. Never use latest.
- Rayfile uses its pinned vendor URL plus archive/binary checksums. Preserve its
  managed runtime and forwarding launcher paths; no vendor /usr/local installer.
  Native Raysync state, credentials, logs and transfers remain untouched.
- Topiary uses a fixed published crate/checksum with its lock and the accepted
  Nu grammar revision. Fail if reproducible source evidence is missing.

## Validation

- Use Bash syntax checks, bytecode-free Python compilation and inspected help.
- Use isolated real Git/Stow and Mason compiler fixtures for changed behavior;
  cover error/interruption rollback and cleanup. Remove only these fixtures.
- Do not run full backup/restore, package installation, real builds, transfers,
  credential deployment or Git publication merely to validate a change.
- Report actual checks and skipped external operations. Never label a staged
  source build as full editor/framework acceptance.
- Use the format-2 recipe for tool selection and reporting. A tool with a
  pinned source stays pending until its rebuild starts.

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
