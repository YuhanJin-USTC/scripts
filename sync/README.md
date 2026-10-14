# NAS and Cluster Synchronization

This domain contains preview-by-default NAS synchronization and cluster upload
or download workflows.

## NAS Sync

```bash
nu sync/sync_files.nu <target|all> [--run]
```

Configured targets are `dot_files`, `scripts`, `Code_Program`,
`Simulation`, `Source_Code`, `Under_Graduate`, and `Matlab`.

Without `--run`, rsync previews the selection. Terminal status is also
appended to `~/.cache/sync_files.log`; the history is not rotated or removed
automatically.

```bash
nu sync/sync_files.nu Simulation
nu sync/sync_files.nu all --run
```

NAS exclusions live in `sync/exclude_rules_nas_only`.

## Cluster Upload

```bash
nu sync/windows2cluster.nu \
  <hfcluster|tycluster|wzcluster> \
  <local_directory> \
  <remote_directory> \
  [--run] [--all-files]
```

A relative remote directory is resolved below the selected cluster root. An
absolute remote directory is used unchanged. The default exclusions live in
`sync/exclude_rules_cluster_upload`; `--all-files` bypasses them. Upload uses
`--update` and does not delete remote files.

```bash
nu sync/windows2cluster.nu \
  hfcluster /home/yuhanjin/Simulation/case_a Simulation/case_a

nu sync/windows2cluster.nu \
  hfcluster /home/yuhanjin/Simulation/case_a Simulation/case_a --run
```

## Cluster Download

```bash
nu sync/cluster2windows.nu \
  <ssh_host> <remote_directory> <local_directory> \
  [prefix] [suffix] [--run]
```

The optional prefix and suffix form the flat file filter `prefix*suffix`.
Omitting both transfers all files selected by rsync.

```bash
nu sync/cluster2windows.nu \
  hfcluster /remote/results /mnt/d/results bz .sdf
```

## Fast Cluster Transfer

The fast-transfer scripts follow the same Nushell comments, colored status
labels and `Target`, `Mode`, `Rule`, command, result output as the rsync scripts.
Their aliases in `dot_files/nushell/.config/nushell/config.nu` are
`fclst2win` and `fwin2clst`. Open a new Nushell session to load them.

```bash
# Download preview
nu sync/fast_cluster2windows.nu wzcluster /Simulation/case_a /local/results

# Upload preview
nu sync/fast_windows2cluster.nu wzcluster /local/case_a /Simulation/case_a

# Additional native excludes
nu sync/fast_cluster2windows.nu wzcluster /Simulation/case_a /local/results \
  --exclude '*.log;*.tmp'

# Bypass only the default upload exclusions
nu sync/fast_windows2cluster.nu wzcluster /local/case_a /Simulation/case_a --all-files
```

Both commands accept a specific file or directory as the source and a
destination directory. Add `--run` to transfer. `--dry-run`/`-n` is explicit
preview; combining it with `--run` is an error. Preview only checks local paths
and prints the command: it does not invoke Rayfile, query a server, request a
token or create the destination. There is no native Rayfile dry-run mode, so
this preview is not a remote file list or a guarantee of remote permissions.

The host tables use the portal commands supplied for all three clusters:

| Target | Short name | Address | Proxy port (`-P`) | User |
| --- | --- | --- | --- | --- |
| `hfcluster` | `hf` | `hefei03.nscc-hf.cn` | `65012` | `yuhanjin` |
| `tycluster` | `ty` | `tycs1.hpccube.com` | `65112` | `yuhanjin` |
| `wzcluster` | `wz` | `wuzh01.hpccube.com` | `65012` | `yuhanjin` |

The small host table is kept at the top of each script, following the existing
upload script. If a portal command changes its endpoint, update both tables.
Ports are service settings, independent of a download token's expiration.
SSH aliases do not determine Rayfile endpoints or credentials.

Remote paths use the portal namespace, such as `/Simulation/case_a`.
Relative `Simulation/case_a` is resolved below the portal root `/`; do not
substitute the SSH home `/work/home/yuhanjin`. Root targets, parent traversal
and control characters are rejected. Source paths are passed directly to
Rayfile; rsync's trailing-slash directory-content semantics are not assumed.
Use a destination directory permitted by the portal token. These scripts do
not run SSH or issue a separate remote `mkdir` request.

At `--run`, enter the portal-generated token at the hidden prompt. For a
non-interactive invocation, provide it through `RAYFILE_TOKEN`. Use a token
authorized for the chosen operation and paths; a download token does not prove
upload permission. No credentials are saved in either repository, and printed
commands show `<hidden>`. The vendor client receives the token through its
required `-w` argument; it can therefore be visible in local process arguments.

Both directions use the user-selected `-file-update rename` policy to retain
same-name files, plus the portal's `-no-meta`, `-symbolic-links follow`, retry
count `10` and timeout `30`. They do not provide rsync's `--update` behavior or
add deletion flags.

Upload reads the existing `exclude_rules_cluster_upload` unless `--all-files`
is supplied. Additional `--exclude` patterns still apply with `--all-files`.
Pass additional wildcard patterns as one semicolon-separated string. Directory
rules such as `.git/` expand to `.git`, `*/.git` and `*/.git/*`; the client gets
one `-exd` argument containing all patterns. Repeated native `-exd` arguments
replace earlier patterns in this version. Inclusion/negation rules are not
supported; invalid patterns stop before any transfer.

The old `prefix`/`suffix` download arguments are intentionally absent, as
agreed. Although an [older vendor example](https://www.raysync.io/news/what-is-new-raysync-released-11-new-functions-in-new-version/)
uses `-reg`, the installed 6.7.8.12 rejects it. This version's native exclusion
parser and rename option were inspected locally; success, directory nesting,
filtering and duplicate renaming on the real server still require an
authorized transfer. No research data was transferred while implementing them.

## Safety and Validation

Rsync preview mode can still read NAS mounts, cluster state, and remote metadata.
Run it only when the exact endpoints and external access are authorized.
For the rsync scripts, trailing slashes intentionally transfer directory
contents rather than nesting the source directory.

Run `nu --ide-check 100` on changed Nushell files. Review endpoints,
constructed SSH/rsync arguments, exclude-rule selection, exit handling, and
preview branching statically. Use only task-created temporary directories for
rule fixtures. For fast transfer, also check offline preview, redacted command
output, token input, single-argument exclusions, file paths with spaces and
nonzero client exit propagation using a local argument-recording fixture.
Do not contact a NAS or cluster merely to validate an edit.
