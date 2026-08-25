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
<!-- digest: 495b19a971d7b9b9af14663fdb4e74e31ef626d7e19a9c856f7fa4b1b28f080e -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, build, or Git mutations without explicit user authorization."
- `framework-authority`: "Use Research Workflow 0.2.2 journal-only Case authority and the unversioned researchctl CLI; historical migrate and migrate-tombstone records remain readable, schema-1 per-Case files and migration commands are unsupported, every multi-device Case write must match the latest synchronized journal head digest, and external synchronization requires explicit user authorization."
- `indexing`: "Treat .research-workflow/index.sqlite3 as local, derived, rebuildable cache only; it is never portable authority."
- `propagation`: "Use exact allowlisted targets, explicit scope approval, and a digest-bound policy apply while preserving unmanaged AGENTS bytes."
- `recording`: "Restore compact context first and record one risk-tiered checkpoint at the most specific owner; unsupported scientific status remains unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through exact knowledge links or explicit user requests."

<!-- research-workflow:policy:end -->
