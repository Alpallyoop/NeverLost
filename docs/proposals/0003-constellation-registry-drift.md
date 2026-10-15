# Proposal 0003 - Constellation registry and managed-file drift for NeverLost

| Field | Value |
|---|---|
| Status | Proposed 2026-10-15 - for Constellation (ecosystem-wide change, made from the `constellation` repository) |
| From | NeverLost readiness audit (`docs/audits/AUDIT_2026-10-15.md`) |
| Changes to NeverLost canonical files | None. Everything below is Constellation-owned. |

## 1. Downstream list is stale in the managed copies

Constellation's registry (`.constellation/registry.json`, registry 2.14.0) lists 13 downstream users of
NeverLost: covenant-gate, recognition, rebound, rooted, live-state-surgeon, watchtower, archive-recall,
contract-registry, gos-runtime, nfl, packetpuncture, runledger, triad.

The Constellation-managed files in this repository still list only the first 6:

- `project.contract.json` -> `ecosystem.downstream_users`
- `docs/canonical/ECOSYSTEM_INTEGRATION.md` -> "Downstream consumers or operators"

Request: regenerate both on the next `constellation.ps1 publish`. NeverLost does not edit them by hand.

## 2. Contract names in the integration registry that NeverLost does not publish

`registry/integrations.json` records these contract names against `neverlost`. NeverLost now publishes a
contract index (`docs/contracts/NEVERLOST_CONTRACTS_v1.md`). Requested normalization:

| Consumer | Recorded name | Request |
|---|---|---|
| packetpuncture | `neverlost.trustbundle.v1` | rename to `neverlost.trust_bundle.v1` |
| packetpuncture | `neverlost.pledge.v1` | NeverLost has no pledge contract. Device pledges are signed under the `watchtower/device-pledge` namespace and verified with `neverlost.sig.verify.v1`; the pledge document itself belongs to WatchTower / Live State Surgeon. Re-point to `neverlost.sig.verify.v1` or to the owning service. |
| soteriavault | `neverlost.contract.v1` | No such contract. Identify what SoteriaVault reads (likely `project.contract.json`, which is Constellation's) and re-point. |
| global-workbench | `neverlost.settings.v1` | No such contract. The workbench UI preferences (`proofs/receipts/authority_preferences.json`, `workbench_mode.json`) are local, not a published contract. Re-point or drop. |
| runledger | `neverlost.allowed_signers.make.v1` | rename to `neverlost.allowed_signers.v1` (the derivation contract) |
| constellation, lawvm | `trust_bundle.v1` | rename to `neverlost.trust_bundle.v1` |
| covenant-gate, live-state-surgeon, proteusops, shutterwall | `None` (declared, unverified) | record the contracts they use from the index once each consumer confirms |

## 3. Dependency-direction note

`scripts/_selftest_watchtower_device_binding_v1.ps1` tested a WatchTower bootstrap script that is not in
this repository. Because NeverLost is upstream of WatchTower, the test was archived
(`scripts/_archive/`) and belongs in the WatchTower repository.

## 4. Another service writes into this repository

`runtime/shadow_profiles/neverlost/` holds Contract Registry output (`contract_registry.ai_use_profile_receipt.v1`,
`data_platform_profile`), written with absolute `C:\dev\neverlost\...` paths. A service writing its evidence
into another service's working tree is filesystem coupling the shared rules prohibit. Request: Contract Registry
writes shadow profiles under its own evidence root, keyed by service id. NeverLost now ignores
`runtime/shadow_profiles/` in Git and does not read it.

## Compatibility impact

None for NeverLost behavior. Consumers that key on the old names keep working until Constellation
renames them; the contract index maps every recorded name.
