# ASR and Translation Instructions

## Scope

These rules apply only under `asr_mt_scripts/` and supplement the
repository-root instructions. Changes confined here use
`root:scripts:asr_mt_scripts` as their V0 event owner.

## Pipeline Invariants

- Preserve the three-stage workflow: Whisper transcription, optional offline
  NLLB translation, and optional FFmpeg subtitle burn-in.
- `asr_mt.nu` is real-only. Source media and generated SRT/video files are user
  content; do not use them as fixtures, delete them, or overwrite them without
  explicit authorization. FFmpeg currently uses overwrite mode for the derived
  output name, so keep that risk visible.
- Preserve fixed container/image assumptions, NVIDIA GPU access in WSL,
  offline translation model use, bind mounts, language codes, and UTF-8 SRT
  output unless the task changes the interface.
- `transcribe.py` and `translate.py` are container-side helpers. Do not create a
  host Python environment, install their heavyweight dependencies, or execute
  model loading as validation.
- Keep transcription, translation, and burn outputs next to the source media
  under their established derived names; any naming or overwrite change must be
  documented with migration risk.

## Validation

- Run `nu --ide-check 100 asr_mt.nu` when Nushell is available.
- Compile changed Python files only as syntax checks; remove only the generated
  `__pycache__` under the repository temporary-cleanup contract.
- Review container arguments, bind paths, output names, language flow, UTF-8
  handling, and FFmpeg construction statically. Do not run Singularity, CUDA
  models, translation, or FFmpeg for routine validation.
<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
