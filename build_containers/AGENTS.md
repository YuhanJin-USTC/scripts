# Container Build Instructions

## Scope

These rules apply under `build_containers/` and supplement the repository-root
instructions. Shared changes confined here use
`root:scripts/build_containers` as their V0 event owner. Use the nearer PIC or
post-processing owner for changes confined to those subtrees.

## Shared Invariants

- `build_common.nu` owns only container-engine selection, stable
  `Target`/`Mode`/`Rule` output, template rendering, and exact temporary
  cleanup.
- Keep PIC and post-processing target records, templates, dependencies, builds,
  and tests in their separate subtrees.
- Stable definitions use `*.def.tmpl`. Render definitions only inside unique
  temporary build directories and reject unresolved placeholders.
- Builds are real by default and use `--force` for configured SIF targets.
  Preserve the `--dry-run` preview interface and show overwrite behavior.
- Remove only task-created temporary build directories, with
  `CODEX_TEMP_CLEANUP=1`. Do not pre-delete a SIF.
- Source_Code and Code_Program are independent authorization scopes. A
  configured path does not authorize modifying either root.

## Validation

- Run `nu --ide-check 100` on changed Nushell files.
- Compare every template placeholder with its renderer record.
- A dry run reads configured paths; use it only when those reads are authorized.
- Never perform a real build or smoke test solely for validation.

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
