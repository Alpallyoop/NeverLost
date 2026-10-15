# Proposal — NeverLost as GOS provider plugin (mirror of gos-runtime 0002)

| Field | Value |
|---|---|
| Status | DRAFT — not canonical |
| Date | 2026-10-09 |
| Primary document | `gos-runtime/docs/proposals/0002-neverlost-contract-consumer-and-provider.md` |

## What this asks of NeverLost

1. **No ownership change.** NeverLost keeps identity, signing, trust and provenance. GOS
   implements a *consumer* of the published v1 contract (trust bundle, principals, SSHSIG)
   and does not redefine it.
2. **A provider-plugin build** of NeverLost for GOS (Android first). Its logic moves from
   PowerShell to a portable implementation, and must match the existing vectors and
   `proofs/receipts` semantics before it can be called NeverLost.
3. **Decisions requested from NeverLost:**
   - Admit a GOS runtime principal (role `gos_runtime_authority`, subject
     `authority/gos-runtime`) into the closed v1 sets, **or** confirm that GOS should re-key
     under an existing role.
   - Ed25519-only vs. admitting ECDSA P-256 for hardware-backed Android keys.
   - A distinct NeverLost root key, so the trust bundle is no longer self-signed.
   - Scope of "identity capture": key enrollment only (proposed), or person capture.
4. **Defects found while consuming the contract** (no fix applied here):
   - `proofs/receipts/admin_plugin/admin_actions.ndjson`: raw newlines inside JSON
     strings make 18 of 25 lines invalid NDJSON. The workbench receipt writer must escape
     `cli_stdout` and `cli_stderr`.
   - `proofs/keys/*.pub` are CRLF, so `pubkey_sha256` depends on line-ending
     conversion.

## NeverLost status (2026-10-15)

- Defect 1 (unescaped newlines in `admin_actions.ndjson`): fixed in
  `scripts/neverlost_admin_plugin_minimal_v1.ps1`; covered by `scripts/_selftest_neverlost_admin_plugin_minimal_v1.ps1`.
  The 18 historic invalid lines stay as written (append-only evidence).
- Defect 2 (CRLF public keys): `pubkey_sha256` is now enforced against the exact file bytes; the
  normalization decision is item A of `0004-trust-root-owner-decisions.md`.
- Decisions requested of NeverLost (role, algorithms, root key, capture scope): items B and E of proposal 0004.
- The portable implementation the provider-plugin needs to match is now specified and vectored:
  `docs/contracts/NEVERLOST_CONTRACTS_v1.md`, `test_vectors/`, `scripts/_RUN_neverlost_vectors_v3.ps1`.

