# Arch Linux Backup and Restore

The Bash entry points preserve the real-by-default workflow and add safe
previews. Full backup/recovery, package transactions, network transfers and builds are
not used merely to validate these scripts; helper fixtures use isolated data.

## Files

| File or path | Purpose |
| --- | --- |
| `archlinux/backup.sh` | Publish one verified backup set for Git |
| `archlinux/restore.sh` | Select, validate and recover a set |
| `archlinux/backup_set.py` | Manifests, archive validation, safe staging and actual differences |
| `archlinux/nvim_state.py`, `nvim_plugins.lua` | Accepted Neovim generations and offline snapshots |
| `archlinux/topiary_dependencies.py` | Shared ELF interpreter and system dependency resolution for capture and recovery |
| `archlinux/rayfile_state.py` | Pinned Rayfile runtime snapshot |
| `archlinux/mason_tools.py` | Internal pinned Mason capture/reconstruction, exposed through `nvim_state.py` |
| `archlinux/data/github-current/` | Current complete set; ordinary Git tracks its component files |

## Backup

```bash
bash backup/archlinux/backup.sh --help
bash backup/archlinux/backup.sh --preview
bash backup/archlinux/backup.sh
```

Preview lists the scope without reading credentials, running package tools or
creating files. A real run creates a private ID-named work directory in
`data/`. Once all components, hashes and archives pass, Linux atomically
publishes the whole directory at `data/github-current/`. A later success
replaces the previous verified set. Ordinary failures clean the invocation's
staging and preserve the published set. The manifest retains the unique ID.
The scripts worktree archive excludes the whole backup data directory.

| Component | Contents and limits |
| --- | --- |
| Packages | Official/AUR names, observed versions, default shell and explicit versions of `python-pynvim`, `ipython`, `python-matplotlib`, `python-pylatexenc`; availability of old versions is not guaranteed |
| System | Selected Pacman/makepkg, WSL, locale and fstab files |
| Home | Bash files and optional home `AGENTS.md` contents |
| Credentials, encrypted | SSH excluding `.ssh/config`, GPG excluding sockets, rclone, `.codex/.env`, effective global Git configuration |
| dot_files, encrypted | Selected worktree without `.git`, backup payloads or added Codex personal configuration/skills |
| scripts | Selected working files without `.git`, old backup payloads, package-list payloads or caches |
| Research_Workflow | Code, skills, metadata and policy; excludes `workspace.toml`, `.research-workflow`, Git and bytecode |
| topiary | Original `/usr/local/bin/topiary`, accepted fixed-revision Nu grammar at its original cache path, build source/recipe, version and system dependency records; system libraries are not copied over target libraries |
| Neovim | Only the active accepted generation, including actual plugins, their `.git`/local edits, native artifacts, parser/query trees and runtime |
| Rayfile | Managed binary, launcher and verified metadata; optional when absent |
| Tool reconstruction | System provider/IPython paths and distributions; four original-path Mason tools; six configured formatter/linter source/path/version records; private npm names/versions/sources; no entire Mason, Python or Node tree |

No scientific source trees, Data, images or models are included. Encrypted
components also contain their internal file manifests. The rclone file is
copied from the exact supported regular source or its Stow target, without
recursively following arbitrary links. Other links must remain inside their
archive, resolve to an included member and have no cycles. Validation expands
each symlink before applying following `..` components, then checks actual
resolved containment after staging. Unknown links or
special files fail, rather than silently omitting contents.

Only the named component archives, `manifest.json` and `COMPLETE` in
`data/github-current/` are eligible for ordinary Git. Use a private repository
appropriate for the configuration in the plaintext components. Each published
file is limited to 100 MiB. When ready, commit the recovery scripts/rules and
the entire published set together and push that commit. On the other machine
clone or pull that same commit, then use `restore.sh --set
/path/to/scripts/backup/archlinux/data/github-current --preview`.
There is no Git action inside backup or restore. Git history can still contain
previously committed archive versions. Sensitive staging roots use mode 0700;
plaintext archives and manifests use 0600. Original member modes remain inside these protected roots for recovery.
Symmetric GPG operations use an independent 0700 temporary `--homedir`,
`--no-options` and no symmetric passphrase cache; they do not use the source
`.gnupg` as the encryption workspace. The matching isolated agent is stopped
before plaintext cleanup, and shell tracing is disabled around the workflow.
Because `gpgconf` can create its private socket directory while querying it,
the pre-query directory state is recorded; only a newly created empty 0700
directory with the expected owner and identity is accepted. Existing agent
directories are never borrowed or removed.
Task-owned plaintext temporaries are removed on exit. Cleanup uses a
per-invocation path/device/inode record and open directory descriptors; inherited
environment variables or replaced links cannot select another cleanup tree.
Completed archives are retained, not rotated.

The backup requires an accepted Neovim active generation. New or changed editor
configuration must be prepared and validated through the common Neovim lifecycle
before it can be exported. Export freshly validates the active generation and
current core dependencies under its lock, then saves their actual evidence.
Backup does not download, rebuild or activate an editor generation.

## Restore

```bash
bash backup/archlinux/restore.sh --help
bash backup/archlinux/restore.sh --preview
bash backup/archlinux/restore.sh --set /path/to/data/github-current --preview
sudo bash backup/archlinux/restore.sh --set /path/to/data/github-current
sudo bash backup/archlinux/restore.sh --legacy /path/to/old/archlinux
```

`--set` and `--legacy` are mutually exclusive. With neither, real mode asks the
user to choose a complete set; it never chooses the newest automatically.
Preview can list candidates and verify public manifests and archive structure.
It does not decrypt, stage or change targets, so encrypted members and actual
restore differences are still unchecked at that point.

Real recovery requires root and a local terminal. Python, GNU tar, GPG
(including `gpgconf`) and Pacman must be available for preflight; Stow and sudo are installed by the
confirmed package stage, together with bubblewrap for isolated tool/editor
validation. All selected archives are copied
to private staging, checked for architecture, hashes, member types, duplicate
paths, links and space, and decrypted before high-impact writes begin. The
archived Research_Workflow code runs its own
`doctor --compatibility-only --store <exact staged STORE.json> --json` check;
the shell does not independently reinterpret Store capabilities or policy.
Existing `metadata/` and `policy/` receive a separate byte/member comparison:
matching authority is skipped, an empty destination may import the selected
snapshot, and any different existing authority stops recovery before high-impact
writes. This prevents replacing newer event tails or choosing a journal fork.
The state is checked again immediately before deployment; imports do not replace
populated authority directories. Keep framework writers stopped during an empty
import. Differences require the separately authorized Research_Workflow
merge/validate workflow; rerunning restore is not a merge strategy. Compatibility
checks and exact file equality are not full framework/device acceptance.
A missing device-local workspace registration is not recreated or borrowed from
the source machine.

Each changed path is shown and confirmed before deployment. Existing content is
preserved in a unique `/root/arch_restore_backup_*` directory; absent or new
files are also shown. Real archived directory mode differences, such as `.ssh`
0700 versus 0777, are confirmed and restored without moving the directory; its
previous mode/owner record is retained. Artificial staging parents are marked
separately, so temporary 0700 permissions do not get applied to existing `/etc`
or other unarchived parents. Unrelated files remain in place. Recovery runs from a separate temporary script copy, allowing selected
`scripts` files to be restored safely. Existing `.git`, previous backup payloads
and package lists are retained; a new machine's worktree is not falsely declared
a Git checkout. No fetch, reset or clean synchronizes user repositories.

Locale enablement and a missing WSL default-user section are prepared as explicit
file differences, confirmed and preserved through the same deployment path.
New-user creation retains wheel membership and `NOPASSWD: ALL`; both preview
and the runtime confirmation state this explicitly. Package restoration is a
separately confirmed current-repository upgrade/install, not an exact historic
downgrade. If yay is missing, a separately confirmed stage clones
`https://aur.archlinux.org/yay-bin.git` into a new private directory and runs
`makepkg -si` as the target user, using base-devel and Git installed by the
package stage. Existing explicit local proxy settings and the official-mirror
Pacman retry are preserved and shown in preview. It does not touch user repositories. Failed build evidence is
retained. This source/bootstrap stage is not a frozen binary recovery guarantee.

The effective encrypted `.gitconfig` and rclone files are compared with their
archived Stow sources before deployment. If the bytes differ, choose
`effective` or `repository` explicitly; the display contains paths, sizes,
modes and hashes, never sensitive text. Choosing effective content updates the
exact staged Stow source, whose eventual destination change is separately
confirmed and preserved. Both original versions remain in the encrypted set.
A saved choice is reused only for the same set and matching actual source/link
content. Matching managed links are not temporarily replaced by regular files.

Stow preserves the explicit Git/SSH/rclone conflicts, then prints its real
simulation before link changes are confirmed. It uses ordinary stow deployment
and skips when the native plan has no link/directory changes. On failure,
rollback attempts to return originals whose targets are still absent and
reports any failure; completed links and preserved originals remain available. Earlier stages are not globally rolled
back. Safety backups are never removed automatically.

Neovim format 2 is staged before system changes. The confirmed package stage
installs the selected Arch core packages before any editor acceptance:

| Dependency | Source and retained entry point | Actual acceptance |
| --- | --- | --- |
| `python-pynvim` | Arch; `/usr/bin/python3` provider | Real Neovim Python provider evaluation |
| `ipython`, `python-matplotlib` | Arch; `/usr/bin/ipython3` and system distributions | Cell edit/run, saved output and core conversion integration |
| `python-pylatexenc` | Arch; `latex2text` from the system package | Required editor dependency checks |
| `clangd`, `python-lsp-server`/`pylsp`, `clang-format`, `stylua` | Original Mason package/bin locations | Exact source/version/content checks plus real LSP and formatter smoke tests |
| `isort`, `black`, `shfmt`, `markdownlint`, `clang-tidy`, `pylint` | Recorded executable paths and owning Arch packages (currently `python-isort`, `python-black`, `shfmt`, `markdownlint-cli`, `clang`, `python-pylint`) | Explicit package reconstruction followed by per-tool path/content/source/version checks; formatter/linter integration is a separate level |

The selected system-package solution replaces the broken `~/base` references;
restore does not invent a venv or a wrapper there. Browser Notebook, HTML/PDF
export and terminal inline-image dependencies are outside the selected core.
`rebuild/editor_tools.json` records package versions, source/path metadata,
Python distribution versions and Mason reconstruction input through the single
`nvim_state.py tools --json` interface.
Its `formatter_linter_tools` block retains all six selected formatter/linter
records. Official Arch owners join the existing confirmed package transaction;
tools already covered by the four Mason records reuse that stage. Unknown
sources remain uncovered. After reconstruction,
`nvim_state.py formatter-check <editor_tools.json> --json` reports every tool:
current-repository version or content changes are `unverified`, not an implicit
downgrade or a false exact-version success. The full result is saved as
`formatter-linter-check.json` with the recovery records.

Mason restoration follows staging and the four Arch packages. It prints the
pinned registry, package versions, sources, original targets and network/build
scope, then shows a stable plan identity before reconstruction through
`nvim_state.py mason-restore --expect-identity`. The execution must match that
reviewed action/source/target identity; changed state requires a new preview
and confirmation, not a wider automatic rebuild.
The internal helper preserves previous tools and checks receipts, versions,
LSP initialization/document symbols and formatter behavior. Matching actual
content is validated and skipped. Missing historical sources or dependencies
fail explicitly; no latest-version fallback is allowed. This stage may need
network/build access and is not an offline binary copy. Future source
availability and a real new-machine reconstruction remain unverified until run.

After dependencies are ready, the common Neovim helper compares actual active
config/runtime/plugin/parser content with the snapshot. Identical content is
revalidated without creating or activating another generation. Otherwise it
reuses a matching saved generation or imports an offline candidate, verifies it,
and prints the exact activation
command and stable identity for separate confirmation. Activation requires the
validated identity and rechecks it before switching. The executable and runtime remain paired.
The result must carry successful real provider, cell edit/run, output-save and
`.py`/`.ipynb` round-trip evidence before jukit core is reported verified.
Format 1 without actual plugin payloads is `needs-rebuild`; it never becomes a
ready generation or triggers Lazy downloads. Failed candidates and previous
generations remain available.

The v3 managed launcher exports `PYTHONDONTWRITEBYTECODE=1` for Neovim and
its Python children, including Jukit. Plugin-tree integrity covers every file.
An exact v2 launcher remains recognized; `status --json` reports
`launcher_upgrade_required`. To preview the launcher-only migration:

```bash
python3 -B backup/archlinux/nvim_state.py --home "$HOME" launcher-upgrade --json
```

After reviewing its target, safety copy and hashes, run `launcher-upgrade
--expect-sha256 BEFORE_SHA256 --run --json` with the same helper and home.
The operation saves the exact old launcher and replaces it atomically.
The active pointer and accepted manifest stay in place. Open a new Neovim
process to inherit the new setting.

Topiary stays at `/usr/local/bin/topiary`. Its binary uses the same explicit
file-difference confirmation and safety preservation as other files; matching
bytes and mode skip replacement. Recovery does not create a user launcher or
private Topiary runtime, and does not overwrite `/usr/lib`. Dependency packages
with recorded official sources join the confirmed Arch transaction. Target loader resolution, canonical
library paths and package ownership are checked. Capture and recovery identify
the loader from the binary's ELF `PT_INTERP` and accept single-path and
`interpreter => resolved-path` ldd entries when the canonical paths agree.
Format-2 single-path records remain supported. Library hashes and installed
version differences are shown and retained. Changed unmanaged libraries fail
because their compatibility is unknown. Archive execution (`ldd` and the saved
version check) runs in a network-disabled bubblewrap namespace with only system
programs and loader cache mounted read-only, no user homes or credentials, and
a time limit. The selected Nu grammar is also stored with repository
`https://github.com/nushell/tree-sitter-nu.git`, revision
`18b7f951e0c511f854685dfcc9f6a34981101dd6`, ABI 15, its accepted artifact hash
and original prefetch recipe. Backup refuses missing or changed grammar bytes.
Recovery validates that record before system changes and restores only
`~/.cache/topiary/nu/18b7f951e0c511f854685dfcc9f6a34981101dd6/grammar.so`
through the same difference/confirmation/preservation path. Other cached
languages remain untouched; recovery never downloads or rebuilds grammars.
The binary and grammar are restored before current Neovim validation.
Archive/path/hash/version checks and actual Conform Nu formatting are separate
validation levels; target functional acceptance must come from the real editor
validation result.
A matching Rayfile runtime and target-home launcher are verified and skipped,
without another safety copy or replacement. Tool records and confirmed content
choices are retained below `~/.local/share/arch-recovery/<set-ID>/`. Private npm
installation remains outside the selected automatic recovery and is reported
as uncovered when records exist. The recorded shell must be installed; a
missing `/etc/shells` entry is confirmed and preserved before adding it, while
an already matching default shell is skipped.

After real recovery enters its staged workflow, every exit, including failure
or interruption, prints a component table with
`verified`, `unverified`, `skipped`, `failed`, or `uncovered` and a concrete
reason. Verification is scoped: system/home/credential/worktree components mean
matching contents, permissions and selected links, not boot/login/application
acceptance. In particular, SSH/GPG file hashes do not prove remote SSH
authentication or usable GPG keys. Rayfile adds only its local version check;
Neovim/jukit and Mason report the actual functional checks listed above. Source-side absence reasons survive the restore. Completed stages and
unattempted work remain distinguishable; there is no blanket complete-success
message hiding missing tools. Once safety preservation starts, the same table
is retained in that invocation's safety directory.

Legacy mode warns that separate old archives cannot establish same-batch
consistency. Unsafe payloads still fail preflight. Missing optional snapshots
are explicit omissions; an old Neovim snapshot without its plugins cannot be
activated. A legacy recovery ends with warning exit code **3**, never a false
complete-set success.

### First use and failure recovery

1. On the source machine, inspect the common editor state with
   `python3 -B backup/archlinux/nvim_state.py --home "$HOME" status --json`.
   Export requires an active, accepted generation; see
   [editor preparation and activation](../update/README.md) if none exists.
2. Run `backup.sh --preview`, then invoke `backup.sh` from a local terminal
   when the displayed source scope is approved. Enter and confirm one hidden GPG
   passphrase shared by the credential and dot_files components. Keep that passphrase
   available independently of this set.
3. From the scripts checkout, stage the tools and the complete
   `backup/archlinux/data/github-current/` directory, including any first-time
   deletions of retired tracked archives. Commit and push. On the second
   machine, clone or pull that revision before restoring the published set.
4. On the target Arch/ArchWSL machine, provide Python, GNU tar, GPG and Pacman,
   the selected complete set, and these recovery scripts. Run `restore.sh
   --set /exact/set --preview`, then the corresponding root invocation in a
   local terminal. Review package/network privileges, decrypt the set, and
   approve each real destination difference and any explicit effective-versus-
   repository configuration choice. File confirmations show metadata and hashes,
   not decrypted text. Review the separate pinned Mason reconstruction preview
   after the four Arch core packages are installed.
5. Review the separate Neovim activation command after its candidate validates.
   Recreate device-specific Research_Workflow `workspace.toml`, device/root
   mappings and local acceptance separately; they are deliberately not copied
   from the source machine. Preserve any current local file until that review.

A failed backup leaves the last verified publication available. A hard kill can leave an ignored ID-named staging directory in `data/`.
Do not edit a marker or merge incomplete components to manufacture completeness.
A failed restore stops nonzero and retains safety backups and failed editor
candidates. Rerunning with the same explicit set recomputes current differences and reuses
only content-verified configuration choices. Matching Stow links, Rayfile
content and Neovim generations are skipped rather than backed up again. It does
not erase previous safety copies. Package upgrades/builds already
completed are not rolled back. Failed AUR build directories are reported and
retained as evidence. A declined prompt also stops; previous accepted changes
and their backups remain available.

## Rayfile

The official fast-transfer client uses the same user-runtime snapshot pattern
as Neovim. It does not enter the Pacman/AUR lists or add a new Stow package.
The reviewed release is **6.7.8.12**, Linux x86_64. System libraries remain
managed by Arch. The archive checksum pins the inspected download; it is not
a vendor signature.

| Content | Location |
| --- | --- |
| Executable, official readme, manifest, checksums | `~/.local/share/rayfile-runtime/` |
| Shell entry point | `~/.local/bin/rayfile-c` |
| Portable program snapshot | `backup/archlinux/data/github-current/rayfile.tar.gz` |
| Preserved installation during restore | `~/rayfile_restore_backup_*/` |
| Native client logs | `~/.config/Raysync/` |

The existing Bash and Nushell PATH already includes `~/.local/bin`. The
launcher forwards all arguments without changing the working directory,
proxy settings, source paths or destinations. Do not run the vendor installer:
it copies two unmanaged binaries into `/usr/local`.

### First installation

Run from the `scripts` repository in Bash:

```bash
(
  set -e
  rayfile_tmp=$(mktemp -d /tmp/rayfile-setup.XXXXXXXX)
  trap 'CODEX_TEMP_CLEANUP=1 rm -rf -- "$rayfile_tmp"' EXIT
  curl --fail --location --show-error \
    --proto '=https' --proto-redir '=https' \
    --noproxy wuzh01.hpccube.com --connect-timeout 15 --max-time 300 \
    --output "$rayfile_tmp/fasttrans-client.tar.gz" \
    'https://wuzh01.hpccube.com:65015/efile/share/fasttrans-client.tar.gz'
  python3 -B backup/archlinux/rayfile_state.py install \
    "$rayfile_tmp/fasttrans-client.tar.gz"
)
python3 -B backup/archlinux/rayfile_state.py verify
rayfile-c --version
```

`--noproxy` applies only to this download host. It does not change persistent
proxy configuration. Installation verifies the reviewed archive and executable
hashes, checks the version, and refuses an existing runtime or launcher.
A changed upstream archive requires reviewing the release and updating the
installer constants; never bypass the checksum to fetch an unknown version.

### Backup and recovery

The normal `backup.sh` places `rayfile.tar.gz` inside a new backup set.
It records only the managed runtime and launcher after version and checksum
validation. Native logs, credentials, research data and unfinished transfers
remain outside the snapshot. A missing installation is an explicit absent
component; partial or modified installations fail the new set.

`restore.sh` checks and stages the archive before privileged target changes.
Restoration runs as the target user, without a download or package mutation,
and preserves the prior runtime and launcher in a unique safety directory.
Missing legacy Rayfile snapshots leave the current client unchanged.

Rayfile-only backup and recovery are also available; these commands do not run
the full Arch backup or restore:

```bash
python3 -B backup/archlinux/rayfile_state.py backup /new/empty/path/rayfile.tar.gz

(
  set -e
  rayfile_stage=$(mktemp -d /tmp/rayfile-restore.XXXXXXXX)
  trap 'CODEX_TEMP_CLEANUP=1 rm -rf -- "$rayfile_stage"' EXIT
  mkdir "$rayfile_stage/input"
  python3 -B backup/archlinux/rayfile_state.py stage \
    /selected/path/rayfile.tar.gz "$rayfile_stage/input"
  python3 -B backup/archlinux/rayfile_state.py restore "$rayfile_stage/input"
)
```

The optional `--home /absolute/path` on install, backup, restore and verify
selects an explicit target home. It also supports isolated temporary-home
validation without changing the process HOME. Safety backups are retained.

### Logs and unfinished transfers

A network-isolated startup probe of 6.7.8.12 observed these native log files:

```text
~/.config/Raysync/RayFileClient-YYYYMMDD.log
~/.config/Raysync/debug.log
~/.config/Raysync/license_0.log
```

`--version` exits without creating them. Logs start during normal connection
setup; they are device-local and are not Stow configuration or snapshot input.
The client also probes optional `raysync.ini`, `cloud-storage.ini` and
`config/config.ini` beside the executable; the official bundle supplies none.
Adding such files requires reviewing their contents and the snapshot allowlist.

No successful transfer was performed during installation. Static inspection
found `.raysync.downloading`, `.raysync.temp.downloading`,
`.raysync.check.data` and `.raysync.original.` strings; a download helper
appends `.raysync.downloading` to a file path. These are evidence of temporary
file naming, not proof of which paths this server enables. The actual resume
files, directory and successful resume behavior remain unverified until an
explicitly authorized transfer. Do not treat `-db` or `config/rs.db` as a
verified resume-file destination, and do not auto-remove unfinished transfers.

## Validation

Use `bash -n`, Python `compile()` without bytecode, and inspected `--help` or
preview paths. Isolated fixtures cover archive/hash rejection, unsafe member
paths/types/links, incomplete sets, real target differences and GNU Stow
simulation/deployment. They do not prove real credential decryption, system
recovery, package availability, AUR builds or remote transfers. Those operations
require their own explicit execution authorization.

The separately authorized isolated GPG test passed a fake-data encrypt/decrypt
round trip, corrupt-ciphertext rejection, private agent/socket shutdown and
plaintext cleanup. It used a random test passphrase and no real credentials;
it does not validate the user's existing encrypted archives or keys.

The helpers reject invalid inputs before deployment and propagate errors.
Retain failed sets, valuable build evidence and all safety backups. Remove only
invocation-created temporary paths, using the `CODEX_TEMP_CLEANUP=1` marker.
