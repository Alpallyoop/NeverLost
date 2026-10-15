# Fixture trust root v1

A committed, public-only trust root used by the proof lanes when `NEVERLOST_TRUST_SOURCE=fixture`
(clean clones, cloud sessions, CI). It mirrors the live trust root's shape: same principal and
namespaces, but a fixture key whose private half was discarded when it was generated. It grants nothing
outside tests and must never be copied into `proofs/trust`.

- `trust/trust_bundle.json`: neverlost.trust_bundle.v1, key path `proofs/keys/fixture_watchtower_authority_ed25519.pub`
- `trust/allowed_signers`: derived from the bundle (scripts/make_allowed_signers_v1.ps1 rules)
- `trust/expected_principal0.txt`, `trust/expected_namespaces_principal0.txt`
- `keys/fixture_watchtower_authority_ed25519.pub`
