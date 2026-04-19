# Threat Model — NeverLost v1

## Assets
- trust_bundle.json (root trust)
- allowed_signers (derived verification list)
- receipts log (append-only audit trail)
- private keys (authority + device keys; private material is never stored by NeverLost)

## Threats
- Trust bundle tampering / rollback
- Key substitution (pubkey swapped)
- Signature spoofing
- Receipt deletion/rewrite
- Namespace escalation (principal uses disallowed namespace)

## Mitigations (v1)
- trust_bundle_sha256 recorded in receipts
- pubkey_sha256 enforced against pubkey_path contents
- allowed_signers regenerated deterministically from trust bundle
- ssh-keygen -Y verify enforces principal
- namespace allowed list enforced at verification time (consumer policy)
- receipts are append-only; consumers should hash-chain later if desired (v1.1+)
