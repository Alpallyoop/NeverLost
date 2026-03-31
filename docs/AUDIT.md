# NeverLost Workbench Audit

## Canonical Source of Truth
The PowerShell instrument under C:\dev\neverlost remains canonical.

The desktop workbench does not reimplement trust logic.
It only invokes approved runners and displays results.

## Approved Commands
- run_tier0
- run_vectors
- get_receipt_ledger
- read_file_text

## Forbidden
- arbitrary shell execution
- trust mutation from UI
- reimplementation of validation logic in TypeScript

## Audit Surfaces
- PowerShell stdout/stderr
- proofs/receipts/neverlost.ndjson
- proofs/receipts/workbench_runs/*
