# NeverLost

NeverLost is a deterministic identity and authority session instrument.

## What it does

- start authority
- confirm authority
- end authority
- status inspection

## Proof lanes

- selftest
- vectors
- full green
- freeze

## Quick start

```powershell
.\scripts\neverlost_cli_v1.ps1 -RepoRoot . -Area authority -Action status
.\scripts\neverlost_cli_v1.ps1 -RepoRoot . -Area authority -Action start
.\scripts\neverlost_cli_v1.ps1 -RepoRoot . -Area authority -Action confirm
.\scripts\neverlost_cli_v1.ps1 -RepoRoot . -Area authority -Action end
```

## Proof

```powershell
.\scripts\_selftest_neverlost_cli_v1.ps1 -RepoRoot .
.\scripts\verify_neverlost_cli_vectors_v1.ps1 -RepoRoot .
.\scripts\_RUN_neverlost_tier0_all_green_v1.ps1 -RepoRoot .
.\scripts\_RUN_neverlost_tier0_freeze_v1.ps1 -RepoRoot .
```

## Status

CLI authority lane is:

- implemented
- selftested
- vectored
- full-green
- freeze-proved
