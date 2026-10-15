# NeverLost Canonical Identity

## Service

- Service ID: `neverlost`
- Canonical name: NeverLost
- Ecosystem layer: `foundation.identity-trust`
- Standalone-first: `true`

## Role

NeverLost is the identity, signing, trust, and provenance authority for the Atlas Systems deterministic software ecosystem.

## Owns

- identity-bound signing
- signer identity
- trust verification
- provenance chains
- signature verification contracts

## Does Not Own

- application policy
- message transport
- application workflows
- general storage restoration

## Dependency Boundary

NeverLost has no upstream service dependency for standalone correctness. Downstream services may consume NeverLost identity, signature, trust, provenance, and receipt contracts through explicit versioned artifacts.

