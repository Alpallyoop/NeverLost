# Proposal 0004 - Trust-root decisions for the NeverLost owner

| Field | Value |
|---|---|
| Status | Proposed 2026-10-15 - each item needs the owner's decision; nothing here has been applied |
| From | NeverLost readiness audit (`docs/audits/AUDIT_2026-10-15.md`) |

These items change trust material, canonical identity or principal sets, so an agent must not decide them.
The tooling each one needs is already in the repository.

## A. Public key files use CRLF (from proposal 0001, defect 2)

`proofs/keys/neverlost_authority_ed25519.pub` and `proofs/keys/watchtower_authority_ed25519.pub` end in
CRLF. `pubkey_sha256` in the trust bundle is the hash of those exact bytes, and the verifier now enforces
that (it did not before). It is deterministic as long as the files are not converted, but any LF
normalization (editor, git `core.autocrlf`, copy to Linux) breaks the hash and every lane fails closed.

Options:
1. Keep exact-bytes hashing and never convert the files (status quo, now documented).
2. Normalize both files to LF and update `pubkey_sha256` in `proofs/trust/trust_bundle.json` (and the
   per-profile copies). This changes `trust_bundle_sha256`, which downstream receipts record; consumers that
   pinned the old bundle hash must be told.

Recommendation: 2, once, with an announcement to WatchTower and NFL.

## B. The NeverLost authority key is not in the trust bundle

`proofs/keys/neverlost_authority_ed25519(.pub)` exists, but the bundle trusts only
`single-tenant/watchtower_authority/authority/watchtower`. The bundle itself is unsigned (proposal 0001
asks for "a distinct NeverLost root key, so the trust bundle is no longer self-signed"). Decide:

- the principal for the NeverLost root key (for example `single-tenant/owner/authority/neverlost`) and its
  namespaces (for example `neverlost/trust-bundle`), and
- whether bundles are signed by it (`sign_file_v1.ps1` with that namespace) and consumers verify the
  bundle signature before use.

## C. LawVM receipt-seal signer (proposal 0002)

Ready: `scripts/export_allowed_signers_v1.ps1 -Namespace <ns> -Consumer lawvm -OutPath <file>
[-TrustBundlePath <lawvm bundle>]` publishes a namespace-restricted signer list LawVM can read with no
runtime dependency. Needed from the owner:

- principal and namespace for the seal key (for example `single-tenant/device_agent/lawvm/receipt-seal`
  with namespace `lawvm/receipt-seal`; `device_agent` is in the closed v1 role set),
- whether the key goes in the main bundle or a separate LawVM product bundle (SPEC v1 section 3 says
  bundles are separate per product), and
- custody: where the private key lives and how it is rotated.

## D. Operator profiles do not follow the principal format

`proofs/profiles/alec/profile.json` and its allocation use `"principal":"Admin"` and `"role":"admin"`.
SPEC v1 requires `single-tenant/<role>/<subject>` with a closed role set that has no `admin`. The
Profiles page (`src/pages/Profiles.tsx`) is excluded from the build and its backend commands were removed
in commit be06881. Time allocations per profile also look like application policy, which NeverLost does
not own. Decide: remove the profiles feature, or re-specify it (valid principals, and policy moved to
Covenant Gate).

## E. GOS requests (proposal 0001)

Still open from 0001: admitting a `gos_runtime_authority` role (changes the closed role set, so a SPEC
change), ECDSA P-256 for Android hardware keys (the verifier accepts only `ssh-ed25519` today), and the
scope of identity capture.

## F. Continuous integration

`scripts/_RUN_neverlost_ci_v1.ps1` runs every portable lane on Linux and Windows. A GitHub Actions
workflow is drafted in `docs/proposals/0005-ci-workflow.md`; it is not enabled because private-repository
Actions minutes are paid.
