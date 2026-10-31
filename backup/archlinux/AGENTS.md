# Arch Backup and Restore Instructions

## Scope

These rules apply only under `backup/archlinux/` and supplement the
repository-root instructions. Changes confined here use
`root:scripts/backup/archlinux` as their V0 event owner.

## Protected State

- `backup.sh [--preview]` remains real by default. Build privately in a new
  ID-named directory under `data/`. Publish only a verified COMPLETE set at
  `data/github-current/`; replace the previous validated publication atomically.
  On ordinary failure retain the last publication and clean the owned staging.
- `restore.sh [--set PATH|--legacy PATH] [--preview]` remains real by default.
  Offer the published set for selection; use the manifest ID for restore state.
- Allow only named native component archives, manifest and COMPLETE into Git
  under the published directory. Exclude all backup payloads from the scripts
  snapshot. Git commits and pushes are separate user operations.
- Before deployment, stage and validate every selected archive: decryption,
  internal hashes, safe member types/links, architecture and free space. Run
  the staged Research Workflow compatibility-only doctor against its matching
  staged Store before writing any user destination. Compatibility is not full
  framework acceptance and never performs Store migration.
- Treat Research Workflow metadata/policy as portable authority: skip identical
  bytes/members, permit a complete snapshot only into empty authority, and refuse
  any populated difference before high-impact writes. Recheck just before import;
  never overwrite populated authority or choose journal heads. Merge/validate
  requires its separate authorized workflow and stopped framework writers.
- Show actual destination differences and obtain each exact confirmation before
  replacement. Preserve unique safety backups, home-level AGENTS and unrelated
  parent directories. Keep `.ssh/config` owned by dot_files/Stow.
- Confirm and preserve real archived directory mode/owner changes separately,
  without moving their contents. Mark synthetic staging parents; never copy
  temporary 0700 permissions onto unarchived parents such as `/etc`.
- Preflight all Stow packages together. Compare encrypted effective Git/rclone
  configuration with archived Stow sources; when different, show metadata/hashes
  and require the exact effective/repository choice, preserving both sources.
  Reuse a choice only when set identity and actual content/link still match.
  Preserve matching links; back up exact Git/SSH/rclone targets and restore
  absent targets on backup or Stow failure. Keep completed links and backups.
- Stage sensitive application files before replacement. Preserve matching
  archived symlinks, reject missing targets/unsupported types, and never extract
  link-only members as file contents or write through parent links. Resolve
  archive links component by component before `..`; reject absolute/escaping
  targets, cycles and more than 40 link expansions. Recheck staged resolution.
- Use an independent restore runner when restoring scripts; preserve its `.git`
  and existing protected payloads. Do not force-sync repositories during restore.
  Missing yay requires explicit confirmation before any private temporary AUR
  clone/build/install. No network fallback may be implicit.
- Keep plaintext archives/manifests at 0600 inside private 0700 staging roots;
  retain archived member modes. Remove only invocation-created temporary paths
  with CODEX_TEMP_CLEANUP=1. Clear cleanup variables before use, register exact
  device/inode identities and use descriptor-anchored cleanup. Refuse replaced
  roots, symlinks or inherited environment values as cleanup authority. Preserve
  valuable failed builds/generations and safety backups; never prune them.
- Report every component on success, failure or interruption as verified,
  unverified, skipped, failed or uncovered with a reason. Preserve source absence
  reasons; do not hide incomplete work behind a final generic success.
- Repeated recovery compares actual payloads, modes and links. Skip matching
  Stow links, Rayfile replacement and Neovim generations while retaining their
  required validation; version equality alone is not equivalence.

## Neovim Generations

- Snapshot complete format-2 config, runtime, data and actual plugin trees,
  including `.git`, local edits, native binaries, parsers and queries. Keep
  lockfile/spec provenance and references to external tools; those references
  do not promise system-tool rollback. Preserve the original 22-language parser
  coverage plus latex, recorded grammar revisions and native/site hashes. Rebuild
  for a changed ABI inside candidates without deleting the old artifacts.
- Keep `nvim_state.py` as the sole public lifecycle, with `nvim_plugins.lua`
  sharing explicit startup specs and `mason_tools.py` internal only. Equivalent
  actual active payload is revalidated without creating or activating a new
  generation; otherwise restore imports an offline candidate. Prepare/restore
  never activate. Show the exact activation command for separate confirmation;
  no Lazy sync/clean/update or missing-content download during offline import.
- Keep the launcher bound to one active generation per invocation. Activation
  checks prepared source/expected-active hashes; rollback selects an accepted
  historical generation after payload validation. Both serialize and atomically
  switch active after fresh real validation under the lock. Preserve previous
  and failed generations without pruning.
- Jukit uses `/usr/bin/python3` and `/usr/bin/ipython3`, backed by Arch
  `python-pynvim`, `ipython`, `python-matplotlib`, `python-pylatexenc`; do not
  recreate the broken `~/base` path or invent a venv. Core acceptance requires
  real provider, cell split/merge/run, saved output and conversion checks.
- Rebuild clangd, pylsp, clang-format and stylua at the original
  `~/.local/share/nvim/mason` locations from recorded receipt/source/version,
  registry checksums and Python pins through official Mason APIs. Preview and
  separately authorize network/build scope; isolate builds at the original
  prefix, preserve old tools and publish atomically. Refuse missing exact pins
  or sources; never fall back to latest. Matching content still needs probes.
- Restore order is staging, selected Arch packages, pinned Mason tools, real
  editor core validation, then separately confirmed activation. Notebook browser,
  HTML/PDF export and terminal image backends are separate unselected features.
- Legacy format 1 with absent plugin content is not ready. Report its limitation
  explicitly and retain the legacy exit-3 incomplete guarantee.

## Rayfile Snapshot

- Keep the official client under `~/.local/share/rayfile-runtime` and its
  forwarding launcher at `~/.local/bin/rayfile-c`; preserve the current working
  directory and arguments. Do not use the vendor `/usr/local` installer.
- `rayfile_state.py` owns installation, verification, backup, staging and
  restoration. Installation pins the reviewed archive and binary hashes;
  a changed download requires a new review, never a checksum bypass.
- Snapshot only the managed runtime, launcher and manifests. Native
  `~/.config/Raysync` logs, credentials, research data and unfinished transfers
  remain local and outside the archive. Do not move or clear them on restore.
- Allow the verified `data/github-current/rayfile.tar.gz` in Git. Stage both archive
  and helper before any destination changes. Restore as the target user without a
  download or package mutation; preserve existing runtime and launcher in a
  unique `rayfile_restore_backup_*` directory.
- Reject unsafe archive members, symlinks, duplicates, checksum mismatches,
  partial installations and incompatible architectures. Retain the previous
  snapshot on backup failure. Missing optional snapshots in old backups are
  an explicit skip, never a request to download the latest release.
- Version checks must use only `--version`. Distinguish observed log locations
  from static temporary-file names; resume-file paths and resume success require
  an authorized real transfer. Do not invent a database or redirect state.

## Validation

- Run `bash -n` on each changed shell script.
- Inspect help only after confirming that it returns before state-changing work.
- Review archive members, quoting, privilege guards, traps, safety backup paths,
  ownership, modes, rollback, and failure cleanup statically.
- Check Stow argument handling with the installed binary in task-created
  temporary package and target directories. Do not substitute a mock for this
  check or use user configuration as test data.
- Never run the full backup/restore, package, GPG, credential or real Git
  workflow for routine validation. Use isolated helper fixtures only.
- Validate Neovim candidates with temporary homes and real modules. Cover
  local plugin edits, safe extraction, offline import, stale/atomic activation,
  rollback and retained failed generations. Do not write live configuration,
  plugin directories or protected payloads as a test.
- Validate Rayfile archive round trips, preservation and rollback with its
  real binary and temporary `--home` directories. Do not invoke the full
  backup/restore pipeline merely to test this helper.

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
