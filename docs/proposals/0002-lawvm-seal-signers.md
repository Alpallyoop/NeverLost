# Proposal 0002 - Trusted signers for LawVM receipt seals

| Field | Value |
|---|---|
| Status | Proposed 2026-10-15 - for the NeverLost owner to decide |
| From | LawVM status report (2026-10-14), recorded by Constellation proposal 0011 (integration `lawvm -> neverlost`, planned) |

## Background

LawVM keeps hash-chained receipts of its re-verifications of Covenant Gate decisions. `lawvm seal-receipts` signs
the chain head with an OpenSSH key, and `lawvm verify-receipts -RequireSignature` checks the signature against an
`allowed_signers` file. Today the seal key and `allowed_signers` are managed by hand. LawVM does not own identity,
signing or trust; NeverLost does (`foundation.identity-trust`).

## Request

1. **Signer list.** NeverLost publishes the trusted signer list for LawVM seals in a form LawVM can consume
   (an OpenSSH `allowed_signers` file, or NeverLost's `trust_bundle.v1` from which one is derived), with the
   principal and namespace LawVM should use.
2. **Key custody (ideally).** NeverLost holds the seal key, or defines how it is held and rotated, so that the
   holder of the key is a NeverLost decision rather than whoever ran `seal-receipts`.

## Notes

LawVM's own caveat stands: entries appended after the last seal are protected by the hash chain only, and whoever
holds the key can re-seal. Custody under NeverLost narrows that to NeverLost's rules. No runtime dependency is
introduced: LawVM reads a file NeverLost publishes.

## NeverLost status (2026-10-15)

Request 1 is implementable now: `scripts/export_allowed_signers_v1.ps1 -RepoRoot <root> -OutPath <file>
-Namespace <seal namespace> -Consumer lawvm [-TrustBundlePath <LawVM bundle>]` publishes a verified,
namespace-restricted `allowed_signers` file with a receipt. What remains is the owner's choice of seal
principal, namespace, bundle placement and key custody: item C of `0004-trust-root-owner-decisions.md`.

