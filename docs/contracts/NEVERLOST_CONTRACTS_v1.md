# NeverLost Integration Contracts v1

This is the published contract surface of NeverLost (`neverlost`, layer `foundation.identity-trust`) for
the services that consume it. It describes what the repository implements today and how a consumer
verifies it without trusting NeverLost's word. It does not change NeverLost's canonical role, ownership or
trust boundaries (`docs/canonical/`); where a contract is not implemented, it says so.

Every artifact below is a file. No consumer needs NeverLost running, and no consumer may call into
NeverLost at runtime: consumers read published files and recompute what they rely on.

## Contract index

| Contract id | Kind | Producer | Schema / format | Verifier | Status |
|---|---|---|---|---|---|
| `neverlost.trust_bundle.v1` | trust root | owner, through NeverLost | `schemas/trust_bundle_v1.schema.json` | `scripts/verify_trust_bundle_v1.ps1` | implemented |
| `neverlost.allowed_signers.v1` | derived signer list | `scripts/make_allowed_signers_v1.ps1` | OpenSSH `allowed_signers`, rules below | `NL-AssertAllowedSignersCurrentV1` (run by start, confirm, verify) | implemented |
| `neverlost.allowed_signers.export.v1` | per-consumer signer list | `scripts/export_allowed_signers_v1.ps1` | same format, optionally one namespace | consumer recomputes from the bundle | implemented |
| `neverlost.sig.sign.v1` | identity-bound signing | `scripts/sign_file_v1.ps1` | OpenSSH SSHSIG (`ssh-keygen -Y sign`) | self-verified before success | implemented |
| `neverlost.sig.verify.v1` | signature verification | `scripts/verify_sig_v1.ps1` | exit code + receipt | `ssh-keygen -Y verify` | implemented |
| `neverlost.receipt.v1` | receipt ledger | all NeverLost writers | `schemas/neverlost_receipt_v1.schema.json` | `scripts/verify_receipt_ledger_v1.ps1` | implemented |
| `neverlost.operator.authority.*.v1` | authority lifecycle | `scripts/neverlost_cli_v1.ps1` | receipt family inside `neverlost.receipt.v1` | ledger verifier (strict field set, provenance chain) | implemented |
| `neverlost.cli.vector.v1` | test vectors | this repository | `schemas/neverlost_cli_vector_v1.schema.json` | `scripts/verify_neverlost_cli_vectors_v1.ps1` | implemented |

Contract names recorded in Constellation's integration registry map to the ids above as follows:

| Registry name | Contract here |
|---|---|
| `neverlost.trust_bundle.v1`, `neverlost.trustbundle.v1`, `trust_bundle.v1` | `neverlost.trust_bundle.v1` |
| `neverlost.allowed_signers.make.v1` | `neverlost.allowed_signers.v1` |
| `neverlost.sig.verify.v1` | `neverlost.sig.verify.v1` |
| `neverlost.receipt.v1` | `neverlost.receipt.v1` |
| `neverlost.pledge.v1` (packetpuncture) | not produced by NeverLost; see `docs/proposals/0003-constellation-registry-drift.md` |
| `neverlost.contract.v1` (soteriavault) | not produced by NeverLost; see proposal 0003 |
| `neverlost.settings.v1` (global-workbench) | not produced by NeverLost; see proposal 0003 |

## neverlost.trust_bundle.v1

Location: `proofs/trust/trust_bundle.json` (product-specific bundles may live elsewhere; SPEC v1 section 3:
trust bundles are separate per product, never silently merged).

Verified by `NL-AssertTrustBundleV1` (`scripts/_lib_neverlost_v1.ps1`) and the CLI wrapper
`scripts/verify_trust_bundle_v1.ps1 -RepoRoot <root> [-TrustBundlePath <file>] [-UseExpectedFiles]`.
A bundle is accepted only if all of these hold; every failure throws `TRUST_BUNDLE_INVALID:<CODE>`:

- UTF-8 without BOM, a single JSON object, no unknown fields at any level.
- Shape `principals[]` (current): `schema` is exactly `neverlost.trust_bundle.v1`; `principals` is a
  non-empty array; each principal has `principal` and a non-empty `keys` array, optional `namespaces`.
- Shape `authorities[]` (legacy, accepted until migrated): `version` is `1`; each entry has `principal`,
  `key_id`, `alg`, `pubkey_path`, `pubkey_sha256`, `allowed_namespaces`.
- `principal` matches `single-tenant/<role>/<subject>` with role in the closed v1 set (`owner`,
  `org_admin`, `device_admin`, `operator`, `auditor`, `device_agent`, `watchtower_authority`); principals are unique.
- `alg` is `ssh-ed25519`; `key_id` is unique across the bundle.
- `pubkey_path` is repository-relative with no `..`; the file exists; `pubkey_sha256` equals SHA-256 of
  the file's exact bytes; the file holds an `ssh-ed25519` key; `pubkey` (when present) is the same key.
- The effective namespaces of each key (principal namespaces plus key namespaces) are non-empty, unique,
  and match `^[A-Za-z0-9][A-Za-z0-9._/-]*$`. A key without namespaces is rejected, because an OpenSSH
  signer line without a namespace restriction would be valid for every namespace.

Expectation checks (used by the authority lifecycle): `TRUST_EXPECTED_PRINCIPAL_MISMATCH` when the
expected principal is absent, `TRUST_EXPECTED_NAMESPACES_MISMATCH` when its namespace set differs.

Consumers must run the same checks (or this verifier) and must not trust `pubkey_sha256` without
recomputing it.

## neverlost.allowed_signers.v1 and .export.v1

Derived only from a verified bundle (`NL-AllowedSignersTextV1`):

- one line per key: `<principal> namespaces="<ns1,ns2,...>" ssh-ed25519 <base64>`
- namespaces ordinal-sorted and comma-joined; lines ordinal-sorted; LF line ends; final LF; UTF-8 without BOM
- no key comments, no other options

`proofs/trust/allowed_signers` must be byte-identical to the derivation. Authority start and confirm and
signature verification fail closed with `TRUST_ALLOWED_SIGNERS_STALE` otherwise; rebuild with
`scripts/make_allowed_signers_v1.ps1 -RepoRoot <root>`.

Exports for a consuming service:

```powershell
scripts/export_allowed_signers_v1.ps1 -RepoRoot <root> -OutPath <file> [-Namespace <ns>] [-Consumer <service-id>] [-TrustBundlePath <bundle>]
```

With `-Namespace`, only keys granted that namespace are exported and each line is restricted to it
(`ALLOWED_SIGNERS_NO_MATCHING_SIGNERS` when none is). Each export appends a
`neverlost.allowed_signers.export.v1` receipt with the output and bundle hashes.

## neverlost.sig.sign.v1

```powershell
scripts/sign_file_v1.ps1 -RepoRoot <root> -TargetPath <file> -SigNamespace <ns> -Principal <principal> -KeyId <key_id> -PrivKeyPath <private key> [-OutSigPath <file>]
```

- Refuses (`SIGN_DENIED_UNTRUSTED_SIGNER`, `SIGN_DENIED_NAMESPACE`, `SIGN_DENIED_KEY_MISMATCH`) unless the
  verified bundle grants that principal, key id and namespace and the private key is the private half of
  the trusted public key.
- Never overwrites a signature (`SIGN_OUTPUT_EXISTS`).
- Verifies the new signature against the trusted signer line before printing `OK: signed`.
- Receipt `neverlost.sig.sign.ok.v1` / `.fail.v1` with `alg`, `principal`, `key_id`, `namespace`,
  target and signature hashes.

NeverLost never stores private keys in the repository; `.gitignore` excludes them.

## neverlost.sig.verify.v1

```powershell
scripts/verify_sig_v1.ps1 -RepoRoot <root> -TargetPath <file> -SigPath <sig> -SigNamespace <ns> -Principal <principal>
```

Exit 0 and `OK: verify PASS` only when the bundle verifies, `allowed_signers` is current, and
`ssh-keygen -Y verify` accepts the signature for that principal and namespace. Failure exits non-zero with
`VERIFY_FAILED`, `VERIFY_TIMEOUT` or a `TRUST_*` code. Receipts `neverlost.sig.verify.ok.v1`,
`.fail.v1`, `.timeout.v1`.

## neverlost.receipt.v1 (ledger)

`proofs/receipts/neverlost.ndjson`: append-only, UTF-8 without BOM, LF, one JSON object per line, keys in
ordinal order. Families (identified by `schema`, or by `event_type` for the envelope and run receipts):

| Family | Identifier | Writer |
|---|---|---|
| authority started / confirmed / ended | `neverlost.operator.authority.{started,confirmed,ended}.v1` | CLI lifecycle |
| runtime notes | `neverlost.operator.runtime.v1` | workbench runtime (historic) |
| legacy receipts | `neverlost.receipt.v1` with `action`, `hashes`, `inputs` | Tier-0 build-out (historic) |
| event envelope | `{ts, event_type: neverlost.<name>.vN, data}` | sign, verify, export |
| proof-lane runs | `event_type: neverlost/<lane>` | tier0 full green |

Authority receipts have an exact field set: `action`, `allowed_signers_sha256`, `authority_state`,
`note` (started, ended), `ok`, `principal`, `schema`, `session_id` (SHA-256 hex), `time_utc`,
`trust_bundle_sha256`. `session_id = SHA-256(principal + start time)`.

`scripts/verify_receipt_ledger_v1.ps1 -RepoRoot <root> [-LedgerPath <file>] [-Strict]` fails on any
format defect and reports provenance anomalies (confirm or end without start, confirm after end, double
end, duplicate start) and historic CRLF lines; `-Strict` fails on those as well. The live ledger has 18
known historic anomalies (15 CRLF tier0 run lines from the Windows PowerShell `Add-Content` defect and 3
lifecycle lines from the old fixed-time test lane); both writers are fixed and the lines stay as written
because the ledger is append-only.

Other NeverLost NDJSON files (`proofs/receipts/workbench_modes/*/authority_actions.ndjson`,
`proofs/receipts/admin_plugin/*.ndjson`) are local operator evidence, not part of this contract.
`admin_actions.ndjson` contains 18 historic lines that are not valid JSON (unescaped newlines, fixed
2026-10-15); readers must skip lines that do not parse rather than trust them.

## Authority lifecycle CLI

```powershell
scripts/neverlost_cli_v1.ps1 -RepoRoot <root> -Area authority -Action status|start|confirm|end
```

| Action | Success | Failure |
|---|---|---|
| status | exit 0, `AUTHORITY_STATUS=NONE|ACTIVE|INACTIVE` | |
| start | exit 0, `AUTHORITY_STARTED_OK`, `SESSION_ID=` | exit 2 `AUTHORITY_START_DENIED_ALREADY_ACTIVE`; exit 1 `TRUST_*` (malformed, missing, mismatched or stale trust) |
| confirm | exit 0, `AUTHORITY_CONFIRMED_OK` | exit 1 `NO_ACTIVE_SESSION`, `SESSION_NOT_ACTIVE`, `TRUST_*` |
| end | exit 0, `AUTHORITY_ENDED_OK` | exit 1 `NO_ACTIVE_SESSION`, `SESSION_NOT_ACTIVE` |
| other | | exit 1 `UNKNOWN_AREA`, `UNKNOWN_ACTION` |

Ending authority does not require valid trust, so an operator can always leave the active state.

## Host requirements

- Windows PowerShell 5.1 (canonical lane on Windows) or PowerShell 7.3+ on Windows, Linux or macOS.
- OpenSSH `ssh-keygen` with `-Y sign/verify` (OpenSSH 8.2+).
- Overrides: `NEVERLOST_PS_HOST`, `NEVERLOST_SSH_KEYGEN`, `NEVERLOST_ROOT` (workbench),
  `NEVERLOST_TRUST_SOURCE=live|fixture` (proof lanes).
