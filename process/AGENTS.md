# ASR and Translation Instructions

## Scope

These rules apply only under `process/` and supplement the repository-root
instructions. Changes confined here use `root:scripts/process` as their V0
event owner.

## Pipeline Invariants

- Preserve the three-stage workflow: Whisper transcription, optional offline
  NLLB translation, and optional FFmpeg subtitle burn-in.
- `asr_mt.nu` is real-only. Source media and generated SRT/video files are
  user content; do not use them as fixtures, delete them, or overwrite them
  without explicit authorization.
- Preserve fixed container/image assumptions, NVIDIA GPU access in WSL,
  offline translation, bind mounts, language codes, UTF-8 SRT output, and
  adjacent derived outputs unless the user changes the interface.
- Keep `--beam-size` connected end to end. A failed ASR, translation, or
  FFmpeg command must produce `[ERROR]` and a nonzero exit.
- `transcribe.py` and `translate.py` are container-side helpers. Do not
  create a host Python environment, install heavyweight dependencies, or load
  models for validation.
- Keep machine-readable helper output on stdout and progress or errors on
  stderr. Do not leak raw model output into command substitutions.

## Validation

- Run `nu --ide-check 100 asr_mt.nu`.
- Compile Python source in memory with explicit UTF-8; do not generate
  `__pycache__` or load model dependencies.
- Review container arguments, bind paths, output names, language flow, external
  exit handling, and FFmpeg construction statically.
- Do not run Singularity, CUDA models, translation, or FFmpeg for validation.

<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
