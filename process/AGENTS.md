# ASR and Translation Instructions

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
<!-- digest: 255425630765de0b777c8b315a1469fc936fca419187535850dcd16888fc5f5d -->
## Managed Research Workflow Policy

- `case-confirmation`: "Case ownership alone changes no definition. For registration, definition or lifecycle changes, finish files/checks, show the saved plan, ask and await consent, then apply its digest. Equal definitions add no revision."
- `external-operations`: "Require explicit task authorization for Git, network/API, SSH, cluster, transfer, sync, simulation, MATLAB, builds, containers and SIF operations."
- `framework-authority`: "Use Research Workflow 0.2.4 and its unversioned CLI. Preserve journal-only Cases, original Event fields, migrate/tombstone bindings and immutable streams. Stop on forks."
- `indexing`: "SQLite and saved plans are disposable device-local state. Queries may refresh SQLite. Never sync either or use it as authority."
- `multi-device`: "After a switch, preserve local work and separately authorize sync. Check portable authority with doctor, event merge and validate before context or any portable write. Keep TOML, paths and identity local. Upgrade sequentially with old writers stopped through acceptance."
- `propagation`: "Show pending semantics, exact targets, diffs and stable digest. After user approval, record it with policy approve and apply that digest. Preserve cumulative approvals and unmanaged bytes. Data, Notes and body patches need separate exact scope."
- `recording`: "Restore compact Case, Study, Project or exact root/path context. Record one substantive result at its closest eligible owner, with purpose, result, accepted reasons, checks and limits in summary/evidence. Skip ordinary discussion, empty membership and pending queues."
- `workspace-routing`: "Use verified roots and explicit mappings. Unmapped logical memory is readable. Local access and new writes need registration. Data stays read-only. Scope Notes to exact links/sections and writes to explicit requests."

<!-- research-workflow:policy:end -->
