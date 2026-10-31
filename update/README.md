# Update Workflows

This directory groups Arch Linux package updates, Panabit iWAN route updates,
and GitHub repository publication. Their shared location does not imply a
shared safety mode.

## Arch Linux

```bash
# Preview both phases
bash update/update_archlinux.sh

# Full Arch upgrade, then prepare and validate an editor candidate
bash update/update_archlinux.sh --run

# Limit the operation
bash update/update_archlinux.sh --system-only --run
bash update/update_archlinux.sh --editor-only --run
```

The default is preview. System preview queries official/AUR updates and may use
network access. Editor preview reads local status and source paths only. Query
failures are reported; `checkupdates` exit 2 means there are no updates.

Real mode performs one full official-package transaction with
`sudo pacman -Syu --needed archlinux-keyring`, then the AUR update
before preparing Neovim. It refuses root execution and uses `sudo` only for
Pacman. An editor failure leaves completed system updates in place and retains
candidate diagnostics; it does not switch the active editor or roll back Arch.
Transaction logs distinguish command failures and explicit ALPM hook errors,
including hook errors reported with Pacman exit 0. Failed logs are retained and
the editor phase stops; ordinary text containing the word "error" is not treated
as a failed transaction.

Neovim has one lifecycle helper, shared with backup/restore:

```bash
python3 -B backup/archlinux/nvim_state.py --home "$HOME" status --json
python3 -B backup/archlinux/nvim_state.py --home "$HOME" prepare --json
python3 -B backup/archlinux/nvim_state.py --home "$HOME" prepare --run --json
# Copy edited source config while retaining existing selected versions
python3 -B backup/archlinux/nvim_state.py --home "$HOME" prepare --keep-versions --run --json
# Optional exact candidate path for a reviewed operation
python3 -B backup/archlinux/nvim_state.py --home "$HOME" prepare --generation REVIEWED_ID --run --json
python3 -B backup/archlinux/nvim_state.py --home "$HOME" validate GENERATION --json
python3 -B backup/archlinux/nvim_state.py --home "$HOME" activate GENERATION --json
python3 -B backup/archlinux/nvim_state.py --home "$HOME" activate GENERATION --expect-identity IDENTITY --run --json
python3 -B backup/archlinux/nvim_state.py --home "$HOME" rollback GENERATION --expect-identity IDENTITY --run --json
```

`prepare --run` downloads the official latest stable Neovim release, requires
its published SHA-256 digest, resolves selected plugin versions, builds native
extensions and all 23 declared Treesitter parsers, then validates the candidate.
This retains the 22 legacy languages (including C++, MATLAB, PowerShell, Git
and SSH) and adds LaTeX. Old parser libraries stay in the legacy tree; the
selected libraries are rebuilt for the candidate runtime.
`--keep-versions` retains existing plugin checkout content and runtime versions;
missing plugins/parsers may still require network access and builds. It never
updates the source `lazy-lock.json`, Stow links, active plugins or active runtime.
Prerequisites include Git, Python 3.12+, build tools, tree-sitter CLI,
`bubblewrap`, and the Arch packages `python-pynvim`, `ipython`,
`python-matplotlib`, and `python-pylatexenc` (`latex2text`). These are separate
system dependencies, never implicitly installed by the editor helper. TeX, uv and pipx
are not required for the limited Unicode formula conversion.

Candidates live under `~/.local/share/nvim-runtime/generations/ID`, with a full
configuration, runtime, plugins, parsers, manifest, logs and separate state/cache.
Source configuration and lockfile hashes are checked again before activation.
Preparation and import never activate automatically. Review the exact generated
ID and stable `identity`, then run its printed activation command with
`--expect-identity`. That digest includes configuration/runtime/plugin content,
executable flags and current external tools, and excludes volatile validation
timestamps. Activation performs fresh checks and refuses any identity change. A concurrent operation, stale
source, stale active generation, missing payload or failed validation blocks the
switch. Failed candidates and previous generations are retained; no automatic
pruning is performed.

The launcher at `~/.local/bin/nvim` resolves `active` once, then fixes that
process's runtime and XDG paths. Activation preserves the previous launcher;
first activation also copies the legacy configuration/plugin/parser trees into
a unique safety directory, while leaving the originals in place. Rollback
selects an existing accepted generation. LSP servers, formatters and other
external tools are recorded references, including legacy Mason binaries; their
versions are outside the editor rollback guarantee.

The active pointer and launcher are published by separate atomic renames;
this is not a two-file power-loss transaction. Caught interruptions restore the
prior state. After an uncatchable stop, `status` reports a launcher mismatch as
unavailable and unvalidated. Review and rerun activation of the same generation
to verify and repair that entry point.

Offline validation includes the runtime's version probe. Its sandbox disables
network access, hides host home/mount/temporary directories, and exposes only
the candidate, helper, original Mason root and task-owned writable directories
there. System files remain read-only; this is not a separate virtual machine.

Managed startup disables Lazy bootstrap/automatic installation, Treesitter
installation and Mason installation/registry refresh. Startup and helper use
the same explicit plugin list. New source modules become available together
through the complete candidate configuration copy; no Stow deployment is needed.
Legacy Stow installations using per-file links can temporarily lack newly added
modules until managed activation, so do not use a partially edited configuration
as a validation target.

Managed Markdown renders in normal mode and shows source in insert mode;
`<leader>tm` toggles it. LaTeX uses `latex2text` for limited Unicode output.
Completion uses blink only: Enter accepts the selected/first item, Tab expands
or advances a snippet then opens completion after a word, Shift-Tab goes back
in snippets, Ctrl-j/k select, Ctrl-h/l scroll documentation, Ctrl-y accepts only
an existing selection, Ctrl-n/p open or navigate the menu, and Ctrl-Space keeps
its default behavior. Buffer words and ghost text are enabled. The old cmp
configuration/cache remain preserved but are absent from the active spec list.

Validation runs real native libraries, parsers, queries and plugin modules under
an isolated HOME/XDG environment with networking disabled and the host filesystem
read-only. It checks complete startup and explicit plugin loading, completion/LSP
capabilities, Telescope extensions, highlight captures, Vim syntax fallback and
Markdown formula extmarks, actual normal/insert mode changes, toggle and blink
key input. Real LSP initialize/documentSymbol and Jukit core integration checks
also run. This is structural compatibility testing, not a promise
that every interactive workflow or external language server is tested.

### Editing and recovery

Edit the source under `~/dot_files/nvim/.config/nvim`, then prepare a new
candidate. The active generation uses its copied configuration, so later source
edits take effect only after a new successful activation. `status --json` shows
the active ID and known candidates. The candidate lockfile records its actual
checkout commits, while the source lockfile remains untouched. A missing newly
added Lua module indicates an incomplete old Stow view; the lifecycle copies the
whole configuration tree and verifies module resolution inside the candidate.

When preparation fails, use the printed candidate path and its `manifest.json`
and `logs/` to inspect the failure. A failed/unvalidated candidate cannot be
activated. Missing native libraries, parser revisions or external formula tools
are errors; the validator does not download replacements. Correct the specific
prerequisite and prepare a new candidate, or use
`prepare --generation ID --retry --run --json` to retain the failed attempt under
that candidate's `attempts/` directory and retry within the same reviewed target.
Add `--reuse-candidate` to reuse a complete hash-verified inactive candidate or
its most recent complete preserved attempt. This option requires `--retry` and
`--generation`, cannot combine with `--keep-versions`, preserves all old inputs,
and rejects changed version/source constraints. Missing or changed parser
revisions are rebuilt, and every check runs again. Active generations cannot be
reused in place. Unverified partial artifacts require a full retry.
Rerun `validate ID` if only an external tool changed. If source files or the source lock changed, prepare anew.
Use `rollback OLD_ID --expect-identity IDENTITY --run` to select a preserved accepted generation; system
packages, LSP servers, formatters and Python environments are not rolled back by
that command.

Jukit uses `/usr/bin/python3` as its provider and `/usr/bin/ipython3` as its
shell. The four required Arch packages are installed before editor import in
backup/restore. Validation checks the real provider, cell split/merge, IPython
terminal execution, saved output and `.py`/`.ipynb` round trips. Browser notebook
viewers, HTML/PDF export and terminal image backends are separate capabilities;
this workflow installs neither Notebook/nbconvert nor TeX for those features.

The original Mason root remains `~/.local/share/nvim/mason`. `tools --json`
records receipts, registry/source pins, package content and Python dependency
versions for clangd, python-lsp-server, clang-format and stylua. Restoration uses
the official Mason installer and recorded registry hashes/versions, then checks
real LSP initialization/requests and formatter operations. It never substitutes
latest versions or changes those tools to another package manager.

`tools --json` also records the configured `isort`, `black`, `shfmt`,
`markdownlint`, `clang-tidy` and `pylint` commands under `formatter_linter_tools`.
Each record includes the actual executable and canonical path, hash, version,
installed package owner/version and locally available repository. Verified
official Arch packages use the existing full system upgrade/install phase;
recorded versions do not authorize a downgrade. A Mason-provided command refers
to its existing Mason record. Unknown sources remain unavailable for automatic
reconstruction. These records prove source/version observation, not successful
formatting or lint diagnostics; real plugin integration has a separate result.

Topiary remains `/usr/local/bin/topiary` and uses its original cache (the incoming
`XDG_CACHE_HOME`, or `~/.cache`). Only its Conform subprocess receives this cache;
Neovim keeps its generation cache. Existing `TOPIARY_CONFIG_FILE` and
`TOPIARY_LANGUAGE_DIR` values are preserved. The Nu grammar is pinned by
`~/.config/topiary/languages.ncl`; backup includes the matching compiled cache.
For C/C++, clang-tidy gets `clang-analyzer-*` only when no `.clang-tidy` exists
beside the file or in a parent directory. Existing rules, including symlinks,
invalid files and explicitly disabled checks, take precedence; nonzero linter
exits are reported instead of silently appearing as a clean result.

```bash
python3 -B backup/archlinux/nvim_state.py --home "$HOME" tools --json
python3 -B backup/archlinux/nvim_state.py --home "$HOME" formatter-check TOOLS_JSON --json
# SOURCE is the validated format-2 staging directory from backup/restore
python3 -B backup/archlinux/nvim_state.py --home "$HOME" mason-restore TOOLS_JSON SOURCE backup/archlinux/nvim_plugins.lua --json
python3 -B backup/archlinux/nvim_state.py --home "$HOME" mason-restore TOOLS_JSON SOURCE backup/archlinux/nvim_plugins.lua --expect-identity PLAN_IDENTITY --run --json
```

`formatter-check` is read-only. Its per-tool `verified` result means matching
executable content, source and version only; drift is `unverified`, and a source
without a known reconstruction method is `uncovered`. Read these JSON statuses
even when the command exits successfully. Malformed records fail with nonzero
exit status. Real formatting and diagnostic results remain separate evidence.

The Mason preview lists exact packages, versions, sources, paths and network needs.
Real reconstruction builds privately at the original absolute Mason prefix,
preserves existing targets, then publishes and verifies them. Matching tools
receive functional checks without reinstallation. A failure retains diagnostics
and restores this invocation's replacements. Stage, Arch packages, Mason tools,
then editor import/validation is the required restore order.

Direct `restore SOURCE LUA_HELPER --run` also reuses an identical active or
previously imported candidate after checking its actual payload and repeating
real validation. It reports `reused: true` and creates no duplicate generation.
Changed payloads get a new candidate; stale source or predecessor state refuses
reuse. Import never switches the active pointer or repairs a launcher by itself.

The first migration has no older managed generation to select with `rollback`.
Its preserved configuration evidence is separately described in
`~/.local/share/nvim-runtime/migration-baselines/20261031-editor-u2-review/manifest.json`.
Some files are real pre-edit copies and others are explicitly labeled
reconstructions; this does not include the old Neovim 0.12.5 runtime or an OS
rollback. The original plugin/site directories remain untouched.

For manual configuration recovery, use a complete XDG configuration tree and
the explicit system executable; `-u init.lua` alone does not set the correct
module search path. For example, after reviewing the baseline's limits:

```bash
baseline="$HOME/.local/share/nvim-runtime/migration-baselines/20261031-editor-u2-review"
env -u NVIM_MANAGED_GENERATION -u NVIM_APPNAME -u NVIM -u NVIM_LISTEN_ADDRESS \
  -u VIMINIT -u EXINIT -u LUA_INIT -u LUA_PATH -u LUA_CPATH \
  XDG_CONFIG_HOME="$baseline/config" XDG_DATA_HOME="$HOME/.local/share" \
  XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache" \
  VIMRUNTIME=/usr/share/nvim/runtime /usr/bin/nvim
```

This reconstructed legacy startup has not passed the managed acceptance suite
and retains its original automatic installer behavior. It is recovery evidence,
not an assertion that the old runtime or all external dependencies were restored.

## iWAN Routes

```bash
# Preview DNS and managed-route changes
bash update/update_iwan_routes.sh

# Apply after exiting Panabit iWAN
bash update/update_iwan_routes.sh --run
```

The updater resolves configured cluster IPv4 addresses and manages only its
owned `/32` routes. It preserves unrelated custom routes and settings. Real
mode requires custom-route mode and refuses to write while
`mobile_client` is running.

Route state and route-only backups are stored below
`%LOCALAPPDATA%\update_iwan_routes`. Backups are not removed automatically.
Preview reads the live Windows configuration and performs DNS queries.

## GitHub Repository Update

```bash
nu update/update_git.nu /path/to/folder "Commit message"
```

This workflow is real-only. An existing repository must be on `main`; other
branches and detached HEAD are refused before network access or mutation.
The configured `origin` takes precedence over the local directory name. Without
`origin`, the existing `YuhanJin-USTC/<directory-name>` convention is used.
The remote repository must already exist. A new local repository starts on
`main`; this command never renames an existing branch.

After checking the remote, it may add `origin`, stage all files, commit and push
`main`. A clean tree only pushes existing commits. Review the entire target
before using it. Tool_Project development uses short feature branches and
reviewed pull requests; use explicit Git commands there instead of this helper.

The Nushell command is `update_git`; it replaces the old `git_update` name.

## Safety and Validation

Use `bash -n` for Bash wrappers, `nu --ide-check 100` for
`update_git.nu`, and the Windows PowerShell parser for
`update_iwan_routes.ps1`. Help is safe only after verifying that parsing
returns before dependencies and external reads.

Check Git publication guards with an isolated fake `git` command and temporary
directories: non-main/detached refusal before remote access, origin precedence,
missing-origin fallback, clean-tree handling and external failure propagation.
Never use a real repository or network endpoint for these checks.

Do not run package updates, DNS/config previews, iWAN writes, Git commands, or
network operations merely to validate an edit.
