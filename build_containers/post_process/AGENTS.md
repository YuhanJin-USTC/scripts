# Post-Processing Container Instructions

## Scope

These rules apply only under `build_containers/post_process/` and supplement
the container and repository-root instructions. Changes confined here use
`root:scripts/build_containers/post_process` as their V0 event owner.

## Post-Processing Invariants

- Keep the EPOCH Jupyter builder and `post_process_defs/` independent from PIC
  environment, program-image, and smoke-test assets.
- Preserve the configured base image, PyPI index, APT packages, fixed Python
  package versions, output path, and `--force` overwrite rule unless the user
  explicitly changes them.
- Keep the image immutable and free of research data and notebooks.
- Real SDF reads, transfers, cluster execution, scheduler use, and Jupyter
  tunnels are separate authorized workflows.
- After an explicitly authorized real build, validation may inspect the SIF,
  run `pip check`, import configured modules, and check JupyterLab version.
  Do not run those operations merely to validate source edits.

## Validation

- Run `nu --ide-check 100` on the builder.
- Compare every template placeholder with the renderer record and review the
  configured package pins statically.
- A dry run reads configured paths and requires authorization. Never perform a
  real image build solely for validation.

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
