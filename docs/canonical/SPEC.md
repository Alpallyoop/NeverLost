# NeverLost Canonical Spec

## Principal Format

NeverLost v1 principals use:

```text
<tenant>/<role>/<subject>
```

The v1 tenant is `single-tenant`.

The closed v1 role set is:

- `owner`
- `org_admin`
- `device_admin`
- `operator`
- `auditor`
- `device_agent`
- `watchtower_authority`

## Trust Bundle

The canonical v1 trust bundle is `neverlost.trust_bundle.v1`.

The current canonical bundle shape is `principals[].keys[]`. The legacy `version` + `authorities[]` shape is accepted by compatibility tooling and schema validation until all old artifacts are migrated.

## Receipts

Receipts are append-only NDJSON, UTF-8 without BOM, with one JSON object per line. Canonical receipt producers must use stable key ordering and fail closed on malformed trust, missing trust, invalid signatures, stale state, or unknown command contracts.

## Workbench

The desktop workbench is not the trust engine. It may invoke approved NeverLost runners, display bounded evidence artifacts, and record workbench action receipts. It must not own application policy or reimplement trust validation in TypeScript.

