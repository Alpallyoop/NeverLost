# NeverLost v1 SPEC — Identity Layer (LOCKED)

## 1. Principal format (v1)
`principal = "<tenant>/<role>/<subject>"`

Tenant: `single-tenant` (v1)

Role set (closed v1):
- owner
- org_admin
- device_admin
- operator
- auditor
- device_agent
- watchtower_authority

Subject:
- device/<device_id>
- user/<user_id>
- authority/watchtower

## 2. Signatures (v1)
Detached signatures using OpenSSH:
- sign: `ssh-keygen -Y sign`
- verify: `ssh-keygen -Y verify`

Every signature-bearing record must include:
- principal
- key_id
- alg
- sig (detached file path or embedded reference)

## 3. Trust bundle (v1)
Source of truth: `proofs/trust/trust_bundle.json`
Derived file (deterministic): `proofs/trust/allowed_signers`

Trust bundles are **separate per product** (TRIAD vs Clarity vs Watchtower, etc.). No silent merging.

## 4. Receipts (v1)
Append-only NDJSON:
`proofs/receipts/neverlost.ndjson`
UTF-8, no BOM, 1 JSON object per line, canonical JSON ordering.

## 5. Integration expectations
NeverLost provides:
- validation (principal/key_id)
- deterministic allowed_signers generation
- signing/verification wrappers
- auditable receipts

Watchtower consumes:
- trust_bundle.json + allowed_signers
- principal->keys allowlist
- verifies packet/envelope signatures deterministically
