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

## Guarantees

- deterministic
- reproducible
- no silent mutation
