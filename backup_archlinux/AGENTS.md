# Backup and Restore Instructions

## Scope

These rules apply only under `backup_archlinux/` and supplement the
repository-root instructions. Changes confined here use
`root:scripts:backup_archlinux` as their V0 event owner.

## Protected State

- `backup.sh` is a real operation: it rewrites package lists and archives,
  handles credentials through GPG, records the default shell, and inspects Git
  state. Never run it as a harmless check.
- Keep the home configuration archive and restore path aligned. It includes the
  home-level `/home/yuhanjin/AGENTS.md` when that file exists.
- `restore.sh` is a root-only disaster-recovery pipeline. It restores system
  and home configuration, installs packages, restores credentials, creates or
  changes users, runs Stow, and force-synchronizes configured repositories.
- Do not edit payloads under `data/`, encrypted archives, `pkg-lists/`, default
  shell records, SSH/GPG material, or app credentials unless the user names the
  exact artifacts and purpose.
- Never print archive contents, decrypted data, passphrases, key material, or
  credential paths beyond the minimum already required by the interface.
- Preserve timestamped safety backups; never remove them automatically.
- Keep temporary restore paths unique and clean them on success and failure.
  Cleanup may target only temporary paths created by that invocation, not
  preserved safety backups.
- Preserve the exclusion of `.ssh/config` from credential restoration because
  it is owned by dot_files/Stow. Changes to forced Git synchronization,
  package installation, proxy use, privilege boundaries, or backup replacement
  semantics require explicit user authorization and prominent handoff notes.

## Validation

- Run `bash -n` on each changed shell script.
- Review archive member handling, quoting, privilege checks, traps, safety
  backup paths, ownership/mode restoration, and failure cleanup statically.
- The current help paths return before state-changing work and may be inspected.
  Never run backup, restore, package, GPG, Stow, or forced Git steps for routine
  validation.

<!-- research-workflow:policy:start -->
<!-- digest: 6e0a68425ea80ae3d662ae2adc443bc98e23190e505c8a9c36daac2c4fbbe164 -->
## Managed Research Workflow Policy

- `external-operations`: "Do not run cluster, simulation, MATLAB, network, sync, or Git mutations without explicit user authorization."
- `framework-authority`: "Use only current Research Workflow V0 authorities and the unversioned CLI; obsolete V1/V2/V2.1 assets are not runtime authority."
- `propagation`: "Default to local-first and require explicit scope approval plus a digest-bound policy apply while preserving unmanaged AGENTS text."
- `recording`: "Use device-gated preview/write V0 events, record once at the most specific owner, and keep unsupported scientific status unknown."
- `workspace-routing`: "Resolve registered roots through workspace.toml; keep Data read-only and access Notes only through explicit links or requests."

<!-- research-workflow:policy:end -->
