import { invoke } from "@tauri-apps/api/core"
import type {
  AllowedSignersInfo,
  AuthorityStatus,
  EvidenceBundle,
  FileTextResult,
  LatestRunInfo,
  LedgerEntry,
  TrustBundleInfo,
} from "./types"

function sanitizeOutput(text: string): string {
  return text
    .replaceAll("NEVERLOST_TIER0_FULL_GREEN", "Verification Passed")
    .replaceAll("NEVERLOST_VECTORS_FULL_GREEN", "Validation Suite Passed")
    .replaceAll("NEVERLOST_VECTOR_POSITIVE_OK", "Positive Validation Passed")
    .replaceAll("NEVERLOST_VECTOR_NEGATIVE_WRONG_PRINCIPAL_OK", "Wrong Principal Negative Passed")
    .replaceAll("NEVERLOST_VECTOR_NEGATIVE_NAMESPACE_OK", "Namespace Negative Passed")
    .replaceAll("NEVERLOST_VECTOR_NEGATIVE_MALFORMED_SHAPE_OK", "Malformed Shape Negative Passed")
}

function sanitizeBundle(bundle: EvidenceBundle): EvidenceBundle {
  return {
    ...bundle,
    stdout: sanitizeOutput(bundle.stdout),
    stderr: sanitizeOutput(bundle.stderr),
  }
}

export async function runTier0(): Promise<EvidenceBundle> {
  return sanitizeBundle(await invoke<EvidenceBundle>("run_tier0"))
}

export async function runVectors(): Promise<EvidenceBundle> {
  return sanitizeBundle(await invoke<EvidenceBundle>("run_vectors"))
}

export async function getReceiptLedger(): Promise<LedgerEntry[]> {
  return await invoke<LedgerEntry[]>("get_receipt_ledger")
}

export async function readFileText(path: string): Promise<FileTextResult> {
  return await invoke<FileTextResult>("read_file_text", { path })
}

export async function getTrustBundleInfo(): Promise<TrustBundleInfo> {
  return await invoke<TrustBundleInfo>("get_trust_bundle_info")
}

export async function getAllowedSignersInfo(): Promise<AllowedSignersInfo> {
  return await invoke<AllowedSignersInfo>("get_allowed_signers_info")
}

export async function getLatestWorkbenchRuns(): Promise<LatestRunInfo[]> {
  return await invoke<LatestRunInfo[]>("get_latest_workbench_runs")
}

export async function openPath(path: string): Promise<void> {
  await invoke("open_path", { path })
}

export async function getAuthorityStatus(): Promise<AuthorityStatus> {
  return await invoke<AuthorityStatus>("get_authority_status")
}

export async function startAuthority() {
  return await invoke("start_authority")
}

export async function confirmAuthority() {
  return await invoke("confirm_authority")
}

export async function endAuthority() {
  return await invoke("end_authority")
}

export async function copyText(text: string): Promise<void> {
  await navigator.clipboard.writeText(text)
}