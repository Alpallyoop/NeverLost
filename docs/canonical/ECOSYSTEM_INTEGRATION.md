# Ecosystem Integration — NeverLost

## Canonical service identity

| Field | Value |
|---|---|
| Service ID | `neverlost` |
| Canonical name | NeverLost |
| Ecosystem layer | `foundation.identity-trust` |
| Standalone-first | `true` |

## Role

Identity, signing, trust, and provenance authority.

## This service owns

- Identity-bound signing
- Signer identity
- Trust verification
- Provenance chains
- Signature verification contracts

## This service does not own

- Application policy
- Message transport
- Application workflows
- General storage restoration

## Upstream services

- None

## Downstream consumers or operators

- `covenant-gate`
- `recognition`
- `rebound`
- `rooted`
- `live-state-surgeon`
- `watchtower`

## Contract families

- `identity.*`
- `signature.*`
- `trust.*`
- `provenance.*`
- `receipt.*`

## Integration rules

1. This repository must remain independently understandable, testable, buildable, and releasable.
2. Ecosystem integrations extend capability but do not replace standalone correctness.
3. Integrations use explicit, versioned schemas and receipts.
4. No undocumented database sharing, hidden filesystem coupling, or implicit trust is permitted.
5. Producer claims must be independently verified by the receiving boundary where verification is required.
6. Integration failure must not silently corrupt local authoritative state.
7. Missing upstream services must produce an explicit unavailable, unknown, deferred, or failed state according to the local contract.
8. This repository's current implementation must not be treated as the complete product definition.

## Authoritative ecosystem sources

- `.constellation/SERVICE_MAP.md`
- `.constellation/registry.json`
- `.constellation/AGENT_POLICY.md`
- `.constellation/SHARED_INVARIANTS.md`

## Change governance

Changes to this service's ecosystem role, ownership boundaries, upstream dependencies, or downstream responsibilities require:

1. A proposal under `docs\proposals`.
2. A documented compatibility impact.
3. Updated service-map and registry entries.
4. Updated positive and negative integration tests.
5. A new service-map receipt.
