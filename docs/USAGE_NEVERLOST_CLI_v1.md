# Usage — NeverLost CLI v1

## Authority lifecycle

Start:
.\scripts\neverlost_cli_v1.ps1 -RepoRoot . -Area authority -Action start

Confirm:
.\scripts\neverlost_cli_v1.ps1 -RepoRoot . -Area authority -Action confirm

End:
.\scripts\neverlost_cli_v1.ps1 -RepoRoot . -Area authority -Action end

Status:
.\scripts\neverlost_cli_v1.ps1 -RepoRoot . -Area authority -Action status

## Proof

Selftest:
.\scripts\_selftest_neverlost_cli_v1.ps1 -RepoRoot .

Vectors:
.\scripts\verify_neverlost_cli_vectors_v1.ps1 -RepoRoot .

Full green:
.\scripts\_RUN_neverlost_tier0_all_green_v1.ps1 -RepoRoot .

Freeze:
.\scripts\_RUN_neverlost_tier0_freeze_v1.ps1 -RepoRoot .

All proof lanes: `scripts/_RUN_neverlost_ci_v1.ps1 -RepoRoot .` (see README).

Selftest and vectors run in sandbox copies and never touch the live session or ledger.

## Exit codes

- 0 success
- 1 refused or failed (`UNKNOWN_AREA`, `UNKNOWN_ACTION`, `NO_ACTIVE_SESSION`, `SESSION_NOT_ACTIVE`, `TRUST_*`)
- 2 start refused because a session is already active (`AUTHORITY_START_DENIED_ALREADY_ACTIVE`)

Start and confirm verify the trust root first (`docs/contracts/NEVERLOST_CONTRACTS_v1.md`).

## Guarantees

- deterministic
- reproducible
- no silent mutation
