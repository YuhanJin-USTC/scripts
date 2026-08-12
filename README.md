# scripts

Personal research-automation toolkit for laser-plasma theory, PIC simulation,
data movement, workstation maintenance, and local media processing.

This is a script-first repository, not a portable software package. Intentional
external paths, cluster aliases, image names, target records, and job counts
remain explicit so daily research workflows are easy to inspect and edit.

## Design

- Keep the locked workflow domains small and explicit, with independent PIC
  build, post-processing build, runtime, sync, and maintenance boundaries.
- Keep public flags, safety defaults, outputs, and configured research paths
  visible.
- Preview external changes where the workflow supports it.
- Protect credentials, backup payloads, source trees, simulation data, and
  reproducibility.
- Keep PIC image builds, post-processing image builds, and PIC runs separate.

## Environment

The configured environment is:

- Arch Linux under WSL.
- Repository path: `/home/yuhanjin/scripts`.
- Windows mounts: `/mnt/c` and `/mnt/d`.
- NAS mounts: `/mnt/y` and `/mnt/z/金虞焓`.
- SSH aliases: `hfcluster`, `tycluster`, and `wzcluster`.

There is no repository-wide installer or dependency command. Install only the
tools required by the workflow being used.

| Domain | Required tools or resources |
| --- | --- |
| Core scripts | Bash, Nushell, standard Linux utilities |
| Container builds | Apptainer or Singularity, `sudo`, configured source and image paths |
| PIC runs | Apptainer and the configured SIF images |
| NAS and cluster transfer | `rsync`, OpenSSH, configured mounts and SSH aliases |
| Arch backup and restore | `tar`, GPG, Git, Stow, Arch package tools |
| iWAN routes | WSL, `powershell.exe`, `wslpath`, Panabit iWAN 2.1.3 |
| ASR and translation | Singularity, NVIDIA GPU access in WSL, local model images |
| Subtitle burn-in | FFmpeg in addition to the ASR requirements |

## Safety Model

The scripts do not share one execution default. Check the mode before running
any command.

| Workflow | Default | Real action |
| --- | --- | --- |
| `update/update_archlinux.sh` | Preview | Add `--run` |
| `update/update_iwan_routes.sh` | Preview | Exit iWAN, then add `--run` |
| `sync/sync_files.nu` | Preview | Add `--run` |
| `sync/windows2cluster.nu` | Preview | Add `--run` |
| `sync/cluster2windows.nu` | Preview | Add `--run` |
| `clean/clean_files.nu` | Preview | Add `--run`, then type `DELETE` |
| Container image builders | **Real build** | Add `--dry-run` to preview |
| PIC image smoke tests | **Real test** | Add `--dry-run` to preview |
| Backup, restore, key transfer, Git update, PIC run, ASR/MT | **Real** | No dry run |

A preview can still read external state. NAS and cluster rsync previews, iWAN
configuration reads, and DNS lookups require an explicitly scoped request and
available external paths or services. Do not use a real update, transfer,
backup, restore, key deployment, Git mutation, container build, PIC run, or
media pipeline merely to validate source changes.

Important boundaries:

- Sync scripts do not use `rsync --delete`.
- Cluster upload excludes common large outputs unless `--all-files` is used.
- Cleanup deletes only explicit junk after typed confirmation.
- Container builds use `build --force` and may replace an existing SIF.
- Restore installs packages, restores credentials, runs Stow, and force-syncs
  configured repositories.
- SSH key transfer overwrites fixed WSL and Windows destinations.
- Subtitle burn-in uses FFmpeg overwrite mode for its derived output.

## Layout

```text
.
├── AGENTS.md
├── README.md
├── backup/
│   └── archlinux/              # Arch package/config backup and restore
├── build_containers/
│   ├── pic/                    # PIC environment/program builders and tests
│   └── post_process/           # Jupyter post-processing image builder
├── clean/                      # Protected junk cleanup
├── process/                    # ASR, translation, and subtitle burn-in
├── run/                        # Unified EPOCH/Smilei PIC runner
├── sync/                       # NAS and cluster rsync workflows
├── transfer/                   # Cluster SSH-key deployment
└── update/                     # Arch, iWAN, and Git update workflows
```

Detailed guides:

- [Arch backup and restore](backup/README.md)
- [Container builds](build_containers/README.md)
- [ASR and media processing](process/README.md)
- [PIC runs](run/README.md)
- [NAS and cluster sync](sync/README.md)
- [Arch, iWAN, and Git updates](update/README.md)

## Nushell Commands

The corresponding aliases live in
`/home/yuhanjin/dot_files/nushell/.config/nushell/config.nu`.

| Alias | Workflow |
| --- | --- |
| `sync_files` | NAS synchronization |
| `clst2win` | Cluster download |
| `win2clst` | Cluster upload |
| `clean_files` | Protected junk cleanup |
| `bd_pic_envs` | PIC environment-image build |
| `bd_pic_images` | PIC program-image build |
| `bd_post_process_images` | EPOCH Jupyter image build |
| `test_pic_images` | PIC image smoke test |
| `tsf_clst_key` | Cluster SSH-key deployment |
| `backup_archlinux` | Arch backup |
| `restore_archlinux` | Arch restore |
| `update_archlinux` | Arch package update |
| `asr_mt` | ASR/translation/subtitle pipeline |
| `run_epoch_1d`, `run_epoch_2d`, `run_epoch_3d` | EPOCH runners |
| `run_smilei`, `run_smilei_spin` | Smilei runners |
| `update_iwan` | iWAN route update |
| `update_git` | Publish local changes to the matching GitHub repository |

`update_git` replaces the old `git_update` alias. The
`bd_post_process_images` alias is new.

## Quick Reference

Run examples from the repository root.

```bash
# Local-only help
bash backup/archlinux/backup.sh --help
bash backup/archlinux/restore.sh --help
nu process/asr_mt.nu --help
bash run/run_pic.sh --help

# Preview modes; external reads may still occur
bash update/update_archlinux.sh
bash update/update_iwan_routes.sh
nu sync/sync_files.nu all
nu clean/clean_files.nu /path/to/project

# Container configuration previews
nu build_containers/pic/bd_pic_envs.nu smilei --dry-run
nu build_containers/pic/bd_pic_images.nu epoch2d --dry-run
nu build_containers/pic/test_pic_images.nu all --dry-run
nu build_containers/post_process/bd_post_process_images.nu epoch --dry-run
```

## Protected Cleanup

```bash
nu clean/clean_files.nu <target_directory> [--run]
```

Preview mode lists explicit cache/editor junk and empty directories. It protects
credentials, backup data, source, PIC inputs, templates, papers,
configuration, archives, and common research-data formats. Real deletion
requires both `--run` and the exact typed confirmation `DELETE`.

Never use a research directory, mounted drive, NAS path, cluster path, backup
location, or user media as disposable cleanup test data.

## Cluster Key Transfer

```bash
nu transfer/tsf_clst_key.nu
```

This real-only workflow selects the newest matching downloaded key for each
configured cluster and force-copies it to fixed WSL and Windows SSH targets.
Review the source prefixes, destination names, and target directories before
running it. Do not execute it as validation or expose key material in logs.

## EPOCH Source and Image Scope

The EPOCH builders and runners in this repository target only the Generic
source at `/home/yuhanjin/Source_Code/Epoch/Epoch/epoch` and the Generic images
`epoch_epoch1d.sif`, `epoch_epoch2d.sif`, and `epoch_epoch3d.sif`. Existing
Photon Probe or QED sources and SIF images are outside this reorganization and
remain untouched.

The open provenance proposal at
`/home/yuhanjin/Research_Workflow/policy/open-proposals/epoch-sif-provenance.json`
also remains byte-unchanged because the current CLI cannot revise an open
proposal. A future supported revise or supersede workflow must reconcile that
proposal with the Generic-only mapping and the new builder paths.

## Validation

Use the narrowest syntax or static check for an edited file:

```bash
nu --ide-check 100 path/to/script.nu
bash -n path/to/script.sh

python3 -B -c 'import pathlib; p=pathlib.Path("path/to/script.py"); compile(p.read_text(encoding="utf-8"), str(p), "exec")'

ps1_path=$(wslpath -w path/to/script.ps1)
powershell.exe -NoProfile -Command \
  "\$p='$ps1_path'; \$tokens=\$null; \$errors=\$null; [void][System.Management.Automation.Language.Parser]::ParseFile(\$p,[ref]\$tokens,[ref]\$errors); if(\$errors.Count){\$errors; exit 1}"
```

The Python check compiles in memory and does not create `__pycache__`. A
PowerShell parse uses the Windows executable but must not execute the updater.
Inspect help or a preview only after confirming that the path does not trigger
external reads outside the authorized scope.

## Coding-Agent Guidance

Repository-wide instructions live in [AGENTS.md](AGENTS.md). Operational
subtrees with distinct risk or behavior contracts carry a local `AGENTS.md`
that inherits the root rules. Research Workflow V0 events replace obsolete
Cards and Worklogs; read-only inspection and planning do not create an event.
