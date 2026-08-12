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

## Safety and Validation

Preview mode can still read NAS mounts, cluster state, and remote metadata.
Run it only when the exact endpoints and external access are authorized.
Trailing slashes intentionally transfer directory contents rather than nesting
the source directory.

Run `nu --ide-check 100` on changed Nushell files. Review endpoints,
constructed SSH/rsync arguments, exclude-rule selection, exit handling, and
preview branching statically. Use only task-created temporary directories for
rule fixtures. Do not contact a NAS or cluster merely to validate an edit.
