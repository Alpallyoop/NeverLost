# NeverLost

NeverLost is the identity, signing, trust and provenance authority of the Constellation ecosystem
(`neverlost`, layer `foundation.identity-trust`). It owns identity-bound signing, signer identity, trust
verification, provenance chains and signature verification contracts. It does not own application
policy, message transport, application workflows or storage restoration.

Canonical documents: `docs/canonical/`. Contracts for consuming services:
`docs/contracts/NEVERLOST_CONTRACTS_v1.md`. Ecosystem rules: `.constellation/` (read-only copies).

## What it does

- verifies the trust root (`proofs/trust/trust_bundle.json`, `neverlost.trust_bundle.v1`) fail-closed
- derives and exports OpenSSH `allowed_signers` lists from the verified trust root
- signs (identity-bound) and verifies files with OpenSSH SSHSIG
- runs the operator authority lifecycle: status, start, confirm, end
- writes an append-only receipt ledger (`proofs/receipts/neverlost.ndjson`) and verifies it
- a Tauri desktop workbench that runs the approved runners and shows evidence (it is not the trust engine)

## Quick start

```powershell
.\scripts\neverlost_cli_v1.ps1 -RepoRoot . -Area authority -Action status
.\scripts\neverlost_cli_v1.ps1 -RepoRoot . -Area authority -Action start
.\scripts\neverlost_cli_v1.ps1 -RepoRoot . -Area authority -Action confirm
.\scripts\neverlost_cli_v1.ps1 -RepoRoot . -Area authority -Action end

.\scripts\verify_trust_bundle_v1.ps1 -RepoRoot . -UseExpectedFiles
.\scripts\make_allowed_signers_v1.ps1 -RepoRoot .
.\scripts\export_allowed_signers_v1.ps1 -RepoRoot . -OutPath <file> -Namespace <ns> -Consumer <service>
.\scripts\sign_file_v1.ps1 -RepoRoot . -TargetPath <file> -SigNamespace <ns> -Principal <principal> -KeyId <key_id> -PrivKeyPath <key>
.\scripts\verify_sig_v1.ps1 -RepoRoot . -TargetPath <file> -SigPath <file.sig> -SigNamespace <ns> -Principal <principal>
.\scripts\verify_receipt_ledger_v1.ps1 -RepoRoot .
```

## Proof lanes

| Lane | Command | Token |
|---|---|---|
| All portable lanes | `scripts/_RUN_neverlost_ci_v1.ps1 -RepoRoot .` | `NEVERLOST_CI_GREEN` |
| CLI lifecycle selftest | `scripts/_selftest_neverlost_cli_v1.ps1 -RepoRoot .` | `NEVERLOST_CLI_SELFTEST_OK` |
| CLI vectors (12) | `scripts/verify_neverlost_cli_vectors_v1.ps1 -RepoRoot .` | `NEVERLOST_CLI_VECTORS_OK` |
| Trust, signature and ledger vectors | `scripts/_RUN_neverlost_vectors_v3.ps1 -RepoRoot .` | `NEVERLOST_VECTORS_FULL_GREEN` |
| Authority lifecycle (fixed times) | `scripts/_RUN_neverlost_authority_full_green_v1.ps1 -RepoRoot .` | `NEVERLOST_AUTHORITY_TIER0_ALL_GREEN` |
| Admin plugin selftest | `scripts/_selftest_neverlost_admin_plugin_minimal_v1.ps1 -RepoRoot .` | `NEVERLOST_ADMIN_PLUGIN_SELFTEST_OK` |
| Tier-0 all green (writes evidence) | `scripts/_RUN_neverlost_tier0_all_green_v1.ps1 -RepoRoot .` | `NEVERLOST_TIER0_ALL_GREEN` |
| Tier-0 full green (writes evidence + receipt) | `scripts/_RUN_neverlost_tier0_full_green_v1.ps1 -RepoRoot .` | `NEVERLOST_TIER0_FULL_GREEN` |
| Freeze (two runs must match) | `scripts/_RUN_neverlost_tier0_freeze_v1.ps1 -RepoRoot .` | `NEVERLOST_TIER0_FREEZE_OK` |
| Live trust pipeline (ACL + selftest, writes evidence) | `scripts/_RUN_neverlost_trust_pipeline_evidence_v1.ps1 -RepoRoot .` | `NEVERLOST_TRUST_EVIDENCE_OK` |
| MSI package smoke (Windows only) | `scripts/_RUN_neverlost_release_package_smoke_v1.ps1 -RepoRoot .` | |

Selftests and vectors run in sandbox copies under `.scratch/sandbox/` and never write test receipts into
the live ledger or change the live authority session. Negative coverage includes malformed, truncated,
empty, BOM, wrong-schema, unknown-role, unknown-field, wrong-algorithm, corrupted-hash, substituted-key,
missing-key, path-traversal and namespace-less trust bundles; wrong principal and namespace expectations;
stale `allowed_signers`; double start, confirm/end without a session, replayed confirm after end; tampered
payload, wrong namespace, wrong principal, corrupted signature, untrusted signer, overwrite refusal; and
partial, foreign, malformed and replayed ledger lines.

## Working remotely

Prerequisites: PowerShell 7.3+ (`pwsh`), OpenSSH `ssh-keygen` 8.2+, Node 20+ and npm, Rust (stable), and
on Linux the Tauri libraries (`libwebkit2gtk-4.1-dev libgtk-3-dev libsoup-3.0-dev
libjavascriptcoregtk-4.1-dev librsvg2-dev libayatana-appindicator3-dev`).

A clean clone has no `proofs/` (trust material and evidence live only on the home computer), so run the
proof lanes against the committed fixture trust root:

```bash
NEVERLOST_TRUST_SOURCE=fixture pwsh -NoProfile -File scripts/_RUN_neverlost_ci_v1.ps1 -RepoRoot .   # NEVERLOST_CI_GREEN
npm ci && npx tsc --noEmit && npm run build                                                        # frontend type check + build
cargo check --manifest-path src-tauri/Cargo.toml && cargo test --manifest-path src-tauri/Cargo.toml # workbench backend + 3 tests
```

What each proves: the CI runner parses every script and runs the selftests and vectors listed above; the
frontend lanes type-check and bundle the workbench; the Rust lanes compile the workbench backend and test
command admission, evidence-root confinement and host resolution.

Only on the home computer (Windows): the live trust root and its ACL lane, the live receipt ledger,
`npm run tauri build` (MSI), the MSI smoke lane, and Windows PowerShell 5.1 runs of the lanes.

Overrides: `NEVERLOST_PS_HOST` (PowerShell host), `NEVERLOST_SSH_KEYGEN`, `NEVERLOST_ROOT` (workbench
repository root), `NEVERLOST_TRUST_SOURCE=live|fixture`.

## Status

See `docs/canonical/CURRENT_STATE.md` and the latest audit in `docs/audits/`.
