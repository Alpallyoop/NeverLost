# Pipeline Contracts — NeverLost v1 (LOCKED)

## Inputs (must be provided)
- trust_bundle.json (v1)
- public keys referenced by trust bundle (paths)
- principal string (v1)
- namespace string (product-defined)

## Outputs (must be produced)
- allowed_signers (deterministic)
- verification outcome (exit code + stderr)
- receipts entries (append-only)

## Determinism requirements
- UTF-8 no BOM files
- canonical JSON ordering
- no ambient machine defaults; always pass RepoRoot
- derived files must be reproducible from trust_bundle.json
