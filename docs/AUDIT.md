# NeverLost Workbench Audit

## Canonical Source of Truth

The PowerShell instrument under the resolved NeverLost repository root remains canonical.

The desktop workbench does not reimplement trust logic. It invokes approved runners, reads bounded evidence artifacts, and displays results.

## Repository Root Resolution

The workbench resolves the repository root by:

- `NEVERLOST_ROOT` when it points at a NeverLost checkout
- current working directory ancestry
- current executable ancestry

No command contract requires `C:\dev\neverlost` as a hardcoded path. The tray uses the same resolution.

## Host Resolution

- PowerShell host: `NEVERLOST_PS_HOST`, else Windows PowerShell 5.1 on Windows, else `pwsh`.
- `open_path` reveals evidence in Explorer on Windows, and opens the containing folder with `xdg-open` /
  `open` elsewhere. It never executes the evidence file.

## Approved Commands

- `run_tier0`
- `run_vectors`
- `get_receipt_ledger`
- `read_file_text`
- `get_trust_bundle_info`
- `get_allowed_signers_info`
- `get_latest_workbench_runs`
- `open_path`
- `get_authority_status`
- `run_neverlost_cli_action`
- `get_workbench_mode`
- `set_workbench_mode`

## Command Boundaries

- `run_tier0` and `run_vectors` may invoke only named PowerShell runners.
- `run_neverlost_cli_action` may invoke only the NeverLost CLI authority lifecycle area/actions: `start`, `confirm`, and `end`.
- Workbench command admission is a local command-surface safety check, not application policy ownership.
- Application policy remains outside NeverLost's service boundary.
- File reads and system-open requests are limited to trust and receipt evidence roots (canonicalized, so
  `..` traversal is refused).
- Workbench action receipts are written durably; if a receipt cannot be written the command returns an
  error instead of reporting success.

## Forbidden

- arbitrary shell execution
- trust mutation from UI
- application policy ownership
- reimplementation of validation logic in TypeScript
- hidden filesystem coupling outside documented trust and receipt evidence roots

## Audit Surfaces

- PowerShell stdout/stderr
- `proofs/receipts/neverlost.ndjson`
- `proofs/receipts/workbench_runs/*`
- `proofs/receipts/workbench_modes/*/authority_actions.ndjson`
