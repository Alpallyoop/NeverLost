# Archived scripts (historical, do not run)

These scripts are kept for provenance only. They are one-off patchers, diagnostics, superseded runners
and backups from the Tier-0 build-out (2026-02 to 2026-05). Several of them rewrite
`scripts/_lib_neverlost_v1.ps1` or trust artifacts in place, assume `C:\dev\neverlost`, or no longer parse.
None of the proof lanes, the CLI or the workbench reference them, and the parse gate in
`scripts/_RUN_neverlost_ci_v1.ps1` only covers the top-level `scripts/` folder.

Notable entries:

- `_RUN_neverlost_vectors_v1.ps1`, `_RUN_neverlost_vectors_v2.ps1`: superseded by `../_RUN_neverlost_vectors_v3.ps1`.
- `selftest_neverlost_trustbundle_v1.ps1`: superseded by `../selftest_neverlost_trustbundle_v2.ps1`.
- `neverlost_admin_plugin_v1.ps1`: superseded by `../neverlost_admin_plugin_minimal_v1.ps1` (docs/ADMIN_PLUGIN_MINIMAL_v1.md).
- `_selftest_watchtower_device_binding_v1.ps1`: tests `watchtower_device_bootstrap_v1.ps1`, which belongs to
  WatchTower. NeverLost is upstream of WatchTower, so this test cannot live here without reversing the
  dependency direction. It belongs in the WatchTower repository.
- `_RUN_watchtower_sigproof_v1*.ps1`, `_DIAG_*`: early signature experiments; the signature lane is now
  covered by `../_RUN_neverlost_vectors_v3.ps1` (sign, verify, tamper, namespace, principal, stale signers).
- `scripts_RUN_neverlost_trust_pipeline_full_green_v1.ps1`: a broken copy that sat in the repository root.

Archived 2026-10-15 during the Constellation readiness audit (docs/audits/AUDIT_2026-10-15.md).
