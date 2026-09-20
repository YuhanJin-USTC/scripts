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
<!-- digest: 53b828bcd3473143cd53c8eb3790393d6fec47f065abe2b14e0e167f32b593b7 -->
## Managed Research Workflow Policy

- `case-confirmation`: "A Case target does not imply a Case edit. For explicit registration or simulation-definition changes, finish files/checks, show the saved preview, actually ask and await the user, then apply the exact plan. A digest is not consent; unchanged accepted definitions add no revision."
- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, build, or Git mutations without explicit user authorization."
- `framework-authority`: "Use Research Workflow 0.2.3 and the unversioned researchctl CLI. Preserve journal-only Case authority, original Event fields, historical migrate/tombstone bindings, immutable streams, and fail-closed forks."
- `indexing`: "Treat SQLite and saved plans as device-local derived state. Queries may refresh the disposable index; never synchronize it or use it as authority."
- `multi-device`: "Synchronize and check portable authority before context or any portable write after switching devices, including event-only work. Keep local TOML/device/paths, upgrade devices sequentially, and stop old metadata writers until local acceptance. External sync remains separately authorized."
- `propagation`: "Preview pending policy semantics, exact targets and differences; obtain real user approval of the stable digest, record it through policy approve, then apply. Preserve cumulative device approvals and unmanaged AGENTS bytes; Data/Notes and body patches require exact separate scope."
- `recording`: "Restore bounded Case, Study, Project, or exact root/path memory. Record one substantive result as an event at the most specific owner; retain purpose, result, accepted reasons, validation level and limits in existing summary/evidence. Do not log ordinary Q&A or create empty membership or pending queues."
- `workspace-routing`: "Resolve local access through verified roots and explicit mappings. Logical memory may be queried without a local mapping, but new writes require local registration. Keep Data read-only and Notes access within exact authorized links/sections."

<!-- research-workflow:policy:end -->
