# Arch Backup and Restore Instructions

Use root:scripts/backup/archlinux for this directory. Keep both Bash entries at the top level, the eight Python/Lua tools in src/ and both Neovim compatibility links at their original relative paths. Usage belongs in backup/README.md.

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

- `restore.sh [--set PATH|--legacy PATH] [--keep-local-workflow] [--use-tool-proxy] [--preview]`
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
- Use HTTPS only for the two public project transfers and SSH for
  Research_Workflow. Validate the exact GitHub repository at staging and
  deployment. Preserve recorded origins and existing checkouts' Git settings.
- Limit the existing-account SSH fallback to the saved GitHub identity and
  known_hosts under the invocation's private github-ssh directory. Keep strict
  host verification and remove that copy as soon as the source checks finish.
- Use eight numbered stages and indented subtask lines. Preserve native package
  output, streamed parser diagnostics and machine-readable helper stdout.
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
- Restore builds at pinned sources and validates before activation. Use bounded
  retries for interrupted archive downloads and remote Git fetches. Report the
  affected artifact and stream parser progress. Preserve TLS, checksum and Mason
  redirect-host checks. The restore option for tool proxy routing is opt-in.
  Standalone
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
- Cover error/interruption rollback and cleanup in approved isolated fixtures. Real Git/Stow and Mason compiler fixtures require authorization for those operations. Remove only owned temporary artifacts.
- Do not run full backup/restore, package installation, real builds, transfers,
  credential deployment or Git publication merely to validate a change.
- Report actual checks and skipped external operations. Never label a staged
  source build as full editor/framework acceptance.
- Use the format-2 recipe for tool selection and reporting. A tool with a
  pinned source stays pending until its rebuild starts.

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
