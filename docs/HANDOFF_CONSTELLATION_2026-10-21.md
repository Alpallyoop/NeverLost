# NeverLost hand-off to Constellation (2026-10-21)

Answers to NeverLost's section of `.constellation/INTEGRATION_WORK.md` (2026-10-21).

| Item | Status |
|---|---|
| Confirm `single-tenant/device_agent/device/<id>` for WatchTower-verified devices | **Confirmed.** It is the SPEC v1 `device/<device_id>` subject under the `device_agent` role. Recorded in `docs/contracts/NEVERLOST_CONTRACTS_v1.md`. |
| Issue principals: Courier nodes, Covenant Gate decision signer, Echo producer, LawVM seal signers | **Tooling done** (`nl issue`, `nl issue-plan`, `Issue_Identities.cmd`, contract `neverlost.trust.issue.v1`). The plan `config/issuance_plan.v1.json` issues on the owner's computer: `single-tenant/device_agent/covenant-gate` (`covenant-gate/decision`), `.../echo-producer` (`packet/envelope`), `.../lawvm` (`lawvm/receipt-seal`), `.../bountygate` (`bountygate/export`), `.../nfl` (`nfl/ledger-seal`, `nfl/ledger-export`, `nfl/ledger-export-seal`), and `.../observatory` (`observatory/packet`, Observatory's own key, enrolled once `OBSERVATORY.cmd setup` has created it). Courier nodes wait for node ids. |
| Publish the bundle hash out of band | `proofs/published/trust_bundle.sha256` (and `README.md`) is rewritten on every change; each consumer gets `proofs/published/<service>/allowed_signers` and `HANDOFF.md`. |
| Owner: `main` cannot be pushed (build files over 100 MB in its history) | **Resolved 2026-10-21.** Local `main` was the pre-cleanup history (already on GitHub as `backup/local-before-clean-publish` and `backup/s-drive-20261020--main`); it now tracks `origin/main`. |
| Merge `audit/constellation-readiness-2026-10-15` | **Done** (NeverLost PR #1, 2026-10-15; PR #2 followed). Please drop the item. |
| Production identities for Live State Surgeon devices | Waiting on Live State Surgeon: device ids and their public keys (`--pubkey`, consumer custody). The plan lists it as WAITING. |
| A real NFL signing key | In the plan (`single-tenant/device_agent/nfl`, NeverLost custody); NFL then switches from the dev key in its `proofs/keys`. |

## For other services' sections

- BountyGate: principal `single-tenant/device_agent/bountygate`, namespace `bountygate/export`; values for
  `config/integrations.local.json` in `proofs/published/bountygate/HANDOFF.md`.
- Echo Transport: new producer key under NeverLost custody replaces the unencrypted producer key; then
  `trust-import` per `proofs/published/echo-transport/HANDOFF.md`.
- Covenant Courier: after every issue the bundle hash changes; re-run `trust-import` with the new `-ExpectedSha256`.
- Contract Registry: its IDENTITY names principal `single-tenant/contract-registry/authority/contract-registry`,
  whose role is outside the closed v1 set; NeverLost can issue `single-tenant/device_agent/contract-registry`
  (`--pubkey` with its current release signer) when Contract Registry agrees.

NeverLost still emits no integration receipts: it consumes no service. The registered `neverlost > watchtower`
edge has no exchange in code (NeverLost proposal 0003).
