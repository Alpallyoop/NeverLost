# NeverLost Workbench Debug

## Common Failure Classes

### RUNNER_MISSING
Expected PowerShell runner is missing from `<repo root>/scripts` (root resolved from NEVERLOST_ROOT, the working directory or the executable location).

### PROCESS_START_FAILED
PowerShell could not be launched. On Windows the workbench uses Windows PowerShell 5.1; elsewhere `pwsh`. Set NEVERLOST_PS_HOST to override.

### Missing green token
The child process exited but did not emit the required token.

### Nonzero exit
The canonical runner failed. Inspect stdout/stderr shown in UI and evidence files on disk.

## Debug Rule
Always debug the PowerShell instrument first.
Do not patch around failures in the React UI.

### TRUST_BUNDLE_INVALID:<CODE> / TRUST_EXPECTED_* / TRUST_ALLOWED_SIGNERS_STALE
The trust root failed verification; authority start/confirm and signing refuse to run. Run
`scripts/verify_trust_bundle_v1.ps1 -RepoRoot . -UseExpectedFiles` for the exact code. For a stale signer
list run `scripts/make_allowed_signers_v1.ps1 -RepoRoot .`.

### LIVE_TRUST_MISSING
A proof lane found no `proofs/trust/trust_bundle.json`. In a clean clone set `NEVERLOST_TRUST_SOURCE=fixture`.

