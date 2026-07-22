# PIC Image Build Instructions

## Scope

These rules apply only under `build_singularity_image/` and supplement the
repository-root instructions. Changes confined here use
`root:scripts:build_singularity_image` as their V0 event owner. Source_Code and
Code_Program are separate authorization scopes; do not modify them merely
because build records reference them.

## Pipeline Invariants

- Keep environment-image builds, program-image builds, and smoke tests as
  separate stages with explicit target records for EPOCH, Smilei, and
  Smilei-Spin.
- The current build and smoke-test scripts are real-by-default. `--dry-run`
  previews configuration; do not silently invert or rename that interface.
- Keep source paths, output paths, environment images, target image names,
  definition templates, compilers, HDF5 settings, jobs, and executables
  explicit and easy to edit.
- Stable definitions use `*.def.tmpl`. Render `*.def` files and source archives
  only inside unique temporary build directories; preserve `{{NAME}}`
  placeholders and explicit rendering values.
- Builds may use `build --force` for the configured SIF target. Never pre-delete
  a SIF manually, and make overwrite behavior visible before execution.
- Report and remove only the temporary build directory on both successful and
  failed builds. Successful smoke-test directories are removed; failed test
  directories are reported and retained for diagnosis.
- Keep smoke inputs minimal and deterministic while exercising input parsing,
  executable linkage, MPI/HDF5 startup, and a short loop. Preserve a minimal
  spin setup for Smilei-Spin when supported.
- Do not add unused rendered definitions beside templates. If an obsolete
  user-owned definition is found, report its exact path and ask before removal.

## Validation

- Run `nu --ide-check 100` on changed Nushell files when available.
- For template changes, compare every placeholder with the corresponding
  renderer record and confirm no placeholder remains unresolved conceptually.
- For smoke-input changes, review syntax, dimensions, termination time, and the
  configured image/command pairing.
- A build-script `--dry-run` still checks real source, image, and executable
  paths. Run it only when those reads are authorized. Never perform a real
  image build or smoke test solely for validation.

<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
