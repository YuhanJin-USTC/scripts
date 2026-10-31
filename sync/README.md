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
  [prefix] [suffix] [--dry-run|--run]
```

The alias is `clst2win`. `hf`, `ty`, and `wz` select `hfcluster`, `tycluster`,
and `wzcluster`; either spelling is accepted. For these registered clusters,
a relative source is below the SSH home in the table below. Absolute SSH
paths remain unchanged. Other SSH hosts, including `user@server`, retain
their original host and path behavior.

The default and `--dry-run` **run an rsync preview over SSH**. They may prompt
for SSH authentication and read remote metadata. They do not download files
or create the local destination. `--run` creates a missing destination and
downloads. Do not combine the two modes.

```bash
nu sync/cluster2windows.nu \
  wz Code_Program/Epoch/Epoch3d /mnt/d/results

nu sync/cluster2windows.nu \
  wzcluster /work/home/yuhanjin/results /mnt/d/results bz .sdf

# Real transfer, only after reviewing the source and destination
nu sync/cluster2windows.nu \
  wz results /mnt/d/results bz .sdf --run
```

The source directory is removed once: `results/bz001.sdf` becomes
`<local_directory>/bz001.sdf`; selected nested paths remain nested. The
existing rsync options are unchanged: archive, compression, `--partial`,
`--size-only`, and no owner/group/permission/time preservation on the local
side. Equal-size existing files can be skipped even if their contents differ;
different-size files can replace existing local files. This command does not use the
fast command's incoming-file rename policy. It does not delete unrelated files.

### Source Paths

Both download commands accept the registered full SSH path or the same
home-relative path. Only the fast command converts a registered SSH home
prefix into a Rayfile portal path.

| Target | Short name | Registered SSH home | Rayfile portal home |
| --- | --- | --- | --- |
| `hfcluster` | `hf` | `/public/home/yuhanjin` | `/` |
| `tycluster` | `ty` | `/work/home/yuhanjin` | `/` |
| `wzcluster` | `wz` | `/work/home/yuhanjin` | `/` |

For `wz` or `wzcluster`:

| Source argument | `clst2win` SSH source | `fclst2win` portal source |
| --- | --- | --- |
| `Code_Program/Epoch/Epoch3d` | `/work/home/yuhanjin/Code_Program/Epoch/Epoch3d` | `/Code_Program/Epoch/Epoch3d` |
| `/work/home/yuhanjin/Code_Program/Epoch/Epoch3d` | unchanged | `/Code_Program/Epoch/Epoch3d` |
| `/Code_Program/Epoch/Epoch3d` | unchanged absolute SSH path | unchanged absolute portal path |
| `/work/home/yuhanjin2/results` | unchanged | unchanged; the registered home does not match |

The prefix match requires the exact home followed by `/`. The fast command's
`--portal-path` bypasses this conversion and interprets the argument directly
in the portal namespace; a relative portal argument still receives `/`.
Other absolute fast paths remain portal paths. The fast command accepts only
the three registered cluster targets. Do not treat an arbitrary portal path
as an SSH path when switching commands; use the relative form or full SSH
path shown above.

The fast command rejects portal root, the registered SSH home by itself,
`.`/`..` path segments, backslashes and control characters. It also rejects
local root, a local file destination, and symlinks in the destination or its
existing parents. Quote paths containing spaces or shell wildcard characters;
Chinese names and quoted leading, trailing or internal spaces are preserved.
Unicode spelling is not normalized. `Input`, `Path`, and
`Target` show the input and selected namespace before any probe.

The SSH roots match the existing upload/configuration records. The actual
`wz` portal listing for `/Code_Program/Epoch/Epoch3d` has been observed;
the `hf` and `ty` portal mappings have not been verified against those servers.

### Prefix and Suffix

The optional arguments form `prefix*suffix`. With neither argument, all
entries are selected. To select by suffix alone, pass an empty prefix:

```bash
nu sync/fast_cluster2windows.nu wz results /mnt/d/results '' .sdf
nu sync/fast_cluster2windows.nu wz 'results 中文/inner data' '/mnt/d/results 中文' bz .sdf
```

The existing rsync rules are `--include=prefix*suffix --exclude=*`.
**Directory names must also match before their children are reachable.**
For `bz` and `.sdf`, `bz001.sdf` is selected, while `run1/bz001.sdf` is
blocked by `run1`. `bz_dir.sdf/bz001.sdf` passes both levels. No implicit
`--include=*/` is added.

The fast selector supports filename globs `*`, `?`, and balanced `[]` classes.
It rejects `/`, backslash, `**`, malformed classes, controls and POSIX classes.
Matching follows rsync's filename-byte behavior, including `?` on UTF-8 names;
it does not interpret `?` as one arbitrary Chinese character. Bracket classes
also operate on bytes, not whole Chinese characters. Its metadata
guard rejects links, unknown types, duplicate paths and missing parent
directory records. These local selector checks do not establish that a native
server response supplies the necessary metadata.

## Fast Cluster Download

The alias is `fclst2win` in the Stow-managed Nushell configuration. If the
alias is unavailable in the current shell, use the full `nu` command:

```bash
nu /home/yuhanjin/scripts/sync/fast_cluster2windows.nu \
  <hfcluster|tycluster|wzcluster|hf|ty|wz> \
  <remote_directory> <local_directory> [prefix] [suffix] \
  [--portal-path] [--dry-run|--list|--attributes|--ssh-list|--run]
```

| Mode | What happens now |
| --- | --- |
| No mode or `--dry-run` / `-n` | Offline path and filter plan; no token read, native client, server access or destination creation |
| `--list` | Explicit native directory-list probe for this source; no download |
| `--attributes` | Explicit native attributes probe for this exact source path; accepts a directory or one entry path; no download |
| `--ssh-list` | Explicit recursive SSH metadata inventory and prefix/suffix selection; no token or download |
| `--run` | `hf` / `ty` / `wz`: SSH metadata, Rayfile download batches, verification, then local publication; only WZ has live fixture acceptance |

Modes are mutually exclusive. `--portal-path` is a path interpretation option,
not an execution mode. The former download `--exclude` / `-e` option refuses
nonempty values; its interaction with metadata selection is unverified.

```bash
# Safe offline plan; no cluster access
nu sync/fast_cluster2windows.nu \
  wz /work/home/yuhanjin/results /mnt/d/results bz .sdf

# Preserve an absolute portal path literally
nu sync/fast_cluster2windows.nu \
  wz /portal/results /mnt/d/results --portal-path

# Run a probe only after authorizing this exact remote path
nu sync/fast_cluster2windows.nu \
  wz /work/home/yuhanjin/Code_Program/Epoch/Epoch3d /mnt/d/results --list

nu sync/fast_cluster2windows.nu \
  wz /work/home/yuhanjin/Code_Program/Epoch/Epoch3d /mnt/d/results --attributes

# Read the mapped SSH directory metadata only, with selection applied
nu sync/fast_cluster2windows.nu \
  wz results /mnt/d/results bz .sdf --ssh-list

# WZ download after authorizing this source and destination
nu sync/fast_cluster2windows.nu \
  wz results /mnt/d/results bz .sdf --run

# Same workflow on HF/TY; their real-server behavior remains untested
nu sync/fast_cluster2windows.nu hf results /mnt/d/hf_results bz .sdf --run
nu sync/fast_cluster2windows.nu ty results /mnt/d/ty_results bz .sdf --run
```

Probes return the native response for the selected source only. Prefix/suffix
filters are not applied to probe output, the local destination is unused,
and the wrapper does not recursively issue additional requests. The client
receives `-o list -d <portal_source>` or
`-o attributes -s <portal_source> -d <portal_source>`. For attributes, both
path slots hold the same exact object because their server-side precedence
has not been verified; no slot is left to a default path.
Each probe requires explicit authorization for its operation and exact remote
path; an example is not ongoing permission to access that path.

### SSH Metadata Selection

The selected R2 workflow uses explicit SSH metadata when native list/filelist
does not provide reliable types. `--ssh-list` reads the source recursively
through the existing registered SSH alias, using Python 3 `lstat` and directory
operations. It does not read file contents. The portal source `/results` maps
to `<registered SSH home>/results`; `--portal-path` changes input interpretation,
not this verified home mapping. The header and `SSH source` show both paths.

SSH uses the existing configuration, `BatchMode=yes`, and
`StrictHostKeyChecking=yes`; unknown host keys and unavailable batch
authentication fail without prompting or accepting keys. For the current WZ
configuration this is `wuzh02.hpccube.com:65091`; the Rayfile endpoint remains
`wuzh01.hpccube.com:65012`. No key deployment or SSH configuration edit occurs.
The remote host must provide Python 3. The inventory is limited to 10,000
entries, 1 MiB and 45 seconds; incomplete responses refuse selection.

Every source ancestor must be a directory without a symbolic link. The
inventory rejects links, special or unknown types, duplicate paths and missing
parent records before applying the byte-glob selection. This mode neither
downloads nor automatically invokes rsync. Default preview remains offline.

### Hidden Token Input

Start a probe or download from your local WSL terminal. If `RAYFILE_TOKEN` is absent or
empty, the prompt says that paste is supported and input is hidden. Paste
one token line and press Enter. No characters or asterisks appear; only
`Token received (hidden).` confirms receipt. Plain and bracketed paste were
tested with 16,384-character fake tokens. Multiple lines and control
characters are rejected; Ctrl-C cancels and restores terminal settings.

An existing `RAYFILE_TOKEN` environment variable is accepted for local
automation and takes precedence over the prompt. Supply it through your
local secret-handling mechanism; do not put the literal value in shell
history, configuration, logs or chat. Remove it from that shell when finished
(`hide-env RAYFILE_TOKEN` in Nushell; `unset RAYFILE_TOKEN` in Bash). Without
a token and an interactive terminal, the probe refuses instead of reading a
pipe or clipboard. Offline preview and `--ssh-list` never request it. Run reads
SSH metadata first and skips an empty file selection without requesting a token.

The native client requires the token in its `-w` process argument, so local
process inspection may see it during the operation. The wrapper does not save
the token, omits it from output, and removes `RAYFILE_TOKEN` from the native
client's environment. Never paste a full native command containing a token
into a diagnostic report.

### Dependencies and Endpoint Table

Offline plans require Nushell, Python 3.11+ and the sibling
`rayfile_download.py`. Native probes and downloads additionally require `bwrap` and the
managed Rayfile 6.7.8.12 executable at
`~/.local/share/rayfile-runtime/rayfile-c`, with the pinned SHA-256
`f718db7def476df9cdb259e0424b54bb0d0f82ed864adb84c62730b73d01b0a7`.
No installation is attempted by the download command.

| Target | Short name | Address | Proxy port (`-P`) | User |
| --- | --- | --- | --- | --- |
| `hfcluster` | `hf` | `hefei03.nscc-hf.cn` | `65012` | `yuhanjin` |
| `tycluster` | `ty` | `tycs1.hpccube.com` | `65112` | `yuhanjin` |
| `wzcluster` | `wz` | `wuzh01.hpccube.com` | `65012` | `yuhanjin` |

The probe mounts the host filesystem read-only and keeps native HOME and
`/tmp` state ephemeral. It saves no native logs. Output is bounded to 1 MiB
and 45 seconds; over-limit responses are discarded and the client process
group is stopped. Terminal control characters are rendered literally.
Production downloads have no total time limit; the native retry settings remain
one retry and a 10-second retry timeout. The wrapper retains only a bounded
1 MiB tail in memory, extracts fixed error/count fields, and saves no native
log or token. Ctrl-C stops the client process group. A brief active-transfer
message appears every 30 seconds.

### Current Limits and Failures

**Real download is enabled for HF, TY and WZ through the same workflow.**
WZ has passed the tiny real-server fixture below. HF and TY share its parent
batching, staging, completeness, SSH stability and no-overwrite publication
logic, but have not been tested against their servers. Their run prints this
status and proceeds with all runtime checks; it does not ask for an additional
confirmation. Enabling HF/TY does not establish server-side acceptance.

The reviewed client flattens absolute UTF-8 filelist entries to basenames.
The helper therefore downloads one batch per selected parent directory into
an empty, exclusive stage, then restores relative paths. It never batches two
different parents into the same native destination. The source directory is
removed once and inner paths, including duplicate basenames, are retained.

Every batch must have exactly the selected regular files and byte sizes, with
no links or extra objects. A second SSH inventory must match the first in
path, type, size, modification time, inode and device. All batches must pass
before publication. Production verification uses metadata and local sizes;
it does not compute remote payload hashes or establish a filesystem snapshot.

Staging uses a hidden `.rayfile-stage-<id>` directory in the destination or
its nearest existing ancestor, on the destination filesystem. Publication
creates complete files with hard links that cannot replace an existing entry.
An incoming collision becomes `name.1.ext`, then `name.2.ext`, and so on;
existing files stay unchanged. This final naming is handled by the helper,
independently of native rename. A filesystem without hard-link support fails
explicitly; there is no overwrite fallback. Windows-mounted filesystem support
and large-file throughput have not been tested.

Native/verification failures publish no files. If local publication itself
fails or is interrupted, already published complete files remain and the error
reports their count; publication is atomic per file, not across the whole batch.
Task-created stages are cleaned. A small `.rayfile-stage-<id>.failure.json`
beside the stage records the phase, counts and a bounded publication preview,
without token or raw native output. It is retained for diagnosis.

The authorized 2026-10-31 WZ fixture contained seven fake files totaling
85 bytes plus a separate link. Three parent batches reconstructed five selected
files totaling 55 bytes, including Chinese/spaced names, an empty file and
duplicate basenames; all five hashes matched the known fixture. Native rename
preserved different sentinel contents and created `name (2).ext`; helper rename
also preserved existing files. A batch containing a missing item downloaded
one valid file and exited `21`, and was rejected as incomplete. `Failed: 0`
can appear in native summaries and is not itself an error. The original three
SIF files were inspected only through metadata; none was downloaded. Both
remote and local fixture payloads were removed.

The observed `wz` list has timestamps, human-readable sizes and paths but
no explicit entry type or link field. A filename extension or size is not
evidence that an entry is a regular file. The observed `attributes` response
is directory statistics: the three-file directory reports its combined size,
while a single `.sif` path reports zero files and zero bytes. It is not a
reliable file type or `lstat` response. R2 therefore obtains typed inventory
through SSH; `--run` explicitly includes this metadata step. Payloads use only
Rayfile, with no rsync fallback.

| Result | Meaning and next action |
| --- | --- |
| Offline plan exits `0` | Local arguments passed; remote existence and permissions remain unknown |
| Probe exits `3` | Native response obtained without a recognized fatal error; raw metadata alone is insufficient for typed selection |
| Run exits `0` | Selected files verified and published, or an empty selection explicitly skipped |
| Operation exits `1` | Guard, dependency, metadata limit, native error, incomplete download or publication failure; read the diagnostic |
| Operation exits `130` | Interrupted; any completed local publication remains and is counted in the failure diagnostic |
| Conflicting modes / unsupported download exclude | Refused before token input or network access |

The native binary can print Usage or an empty-path error and still exit `0`;
the wrapper treats those messages as failures. A success-looking native
message alone does not establish completeness. There is no automatic rsync
payload fallback or all-files fallback. Ordinary `clst2win` remains available
with its own SSH source path and separately authorized preview/transfer.

## Fast Cluster Upload

The alias is `fwin2clst`. It retains its existing local-only preview and
portal-only destination interpretation; the new download SSH-home mapping
does not change upload behavior.

```bash
# Upload preview; existing exclusions and explicit bypass remain unchanged
nu sync/fast_windows2cluster.nu wz /local/case_a /Simulation/case_a
nu sync/fast_windows2cluster.nu wz /local/case_a /Simulation/case_a --all-files
```

Upload retains its existing `--run`, `--dry-run`, `--exclude`, and
`--all-files` interfaces and native `-file-update rename`, `-no-meta`,
`-symbolic-links follow`, retry `10` and timeout `30`. Its exclusion file is
`exclude_rules_cluster_upload`; `--all-files` bypasses only those defaults.
Additional patterns are merged into one semicolon-separated `-exd` because
repeated options replace earlier patterns. Upload still reads its token only
at run time. Successful transfer, server-side filtering and rename remain
unverified; local argument tests do not establish them.

## Safety and Validation

Rsync preview mode can still read NAS mounts, cluster state, and remote metadata.
Run it only when the exact endpoints and external access are authorized.
For the rsync scripts, trailing slashes intentionally transfer directory
contents rather than nesting the source directory.

Run `nu --ide-check 100` on changed Nushell files. Review endpoints,
constructed SSH/rsync arguments, exclude-rule selection, exit handling, and
preview branching statically. Use only task-created temporary directories for
rule fixtures. For fast transfer, also check offline preview, redacted command
output, long hidden token paste, single-argument exclusions, Chinese paths and
paths with spaces, and nonzero client exit propagation using a local fixture.
Compare selector behavior to rsync only with task-created local files.
Native option checks require an isolated network namespace and fake tokens.
Do not contact a NAS or cluster merely to validate an edit. Local validation
does not verify server metadata, download layout, rename or performance.
