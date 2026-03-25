# NeverLost v1 — Canonical Identity Layer

NeverLost is the canonical identity layer for the ecosystem:
- **principals**
- **trusted keys**
- **detached signatures** (ssh-keygen -Y)
- **deterministic trust bundles**
- **append-only receipts**

## Contract (LOCKED v1)
Principal: `<tenant>/<role>/<subject>`

Role set:
`owner | org_admin | device_admin | operator | auditor | device_agent | watchtower_authority`

Subject:
- `device/<device_id>`
- `user/<user_id>`
- `authority/watchtower`

## Quick start
1) Create an authority keypair (example):
`ssh-keygen -t ed25519 -f proofs\keys\neverlost_authority_ed25519 -N '""' -C "neverlost_authority_ed25519"`

2) Create/maintain `proofs\trust\trust_bundle.json` (see schemas).

3) Generate allowed_signers:
`pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\make_allowed_signers_v1.ps1 -RepoRoot "C:\dev\neverlost"`

4) Show identity:
`pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\show_identity_v1.ps1 -RepoRoot "C:\dev\neverlost"`
