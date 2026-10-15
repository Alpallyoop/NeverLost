# NeverLost Current State

Updated 2026-10-15 (readiness audit: `docs/audits/AUDIT_2026-10-15.md`).

## Status

NeverLost currently contains:

- canonical PowerShell authority lifecycle and proof runners (Windows PowerShell 5.1 and PowerShell 7 on
  Windows, Linux and macOS; host resolution in `scripts/_lib_neverlost_host_v1.ps1`)
- a fail-closed trust-bundle verifier (`NL-AssertTrustBundleV1`, `scripts/verify_trust_bundle_v1.ps1`)
- identity-bound signing and verification wrappers over OpenSSH SSHSIG
- `allowed_signers` derivation and per-consumer export (`scripts/export_allowed_signers_v1.ps1`)
- a receipt-ledger verifier (`scripts/verify_receipt_ledger_v1.ps1`)
- published integration contracts (`docs/contracts/NEVERLOST_CONTRACTS_v1.md`) and schemas (`schemas/`)
- one command line, `nl` (`scripts/nl.ps1`, `nl.cmd`), and Windows double-click launchers (`*.cmd` in the
  repository root) for status, update, push, identity checks, tests and ecosystem needs
- a Tauri desktop workbench for local operation and evidence display
- trust-bundle and allowed-signers artifacts under `proofs/trust` (local, untracked)
- receipt-ledger artifacts under `proofs/receipts` (local, untracked)
- a committed public-only fixture trust root (`test_vectors/fixtures/trust_root_v1`) for clean clones and CI

## Verified Lanes

- All portable proof lanes: `scripts/_RUN_neverlost_ci_v1.ps1` (`NEVERLOST_CI_GREEN`)
- CLI selftest: `scripts/_selftest_neverlost_cli_v1.ps1`
- CLI vectors: `scripts/verify_neverlost_cli_vectors_v1.ps1` (12 vectors)
- Trust, signature and ledger vectors: `scripts/_RUN_neverlost_vectors_v3.ps1`
- Tier-0 full green and freeze: `scripts/_RUN_neverlost_tier0_full_green_v1.ps1`, `scripts/_RUN_neverlost_tier0_freeze_v1.ps1`
- TypeScript check: `npx tsc --noEmit`
- frontend build: `npm run build`
- Rust check and tests: `cargo check`, `cargo test` from `src-tauri`

Selftests and vectors run in sandbox copies (`.scratch/sandbox`) and never write to the live ledger.

## Known Transitional Areas

- The trust-bundle schema and verifier accept both the current `principals[].keys[]` shape and the legacy
  `version` + `authorities[]` shape until all old artifacts are migrated.
- Proof artifacts, trust material and keys are local evidence and are not tracked in Git.
- The workbench stores local UI preferences separately from canonical trust and receipt artifacts.
- The live receipt ledger holds 18 historic anomalies written by since-fixed defects (15 CRLF run lines,
  3 replayed lifecycle lines from the old fixed-time test lane); the ledger is append-only, so they remain.
- Operator profiles (`proofs/profiles/`, `src/pages/Profiles.tsx`) do not follow the v1 principal format and
  are excluded from the build; owner decision pending (`docs/proposals/0004-trust-root-owner-decisions.md` item D).
- Open owner decisions on trust material: `docs/proposals/0004-trust-root-owner-decisions.md`.
- Constellation-managed drift (downstream list, contract names): `docs/proposals/0003-constellation-registry-drift.md`.
