import { invoke } from "@tauri-apps/api/core"

import type {
  AllowedSignersInfo,
  AuthorityStatus,
  CliActionResult,
  EvidenceBundle,
  FileTextResult,
  LatestRunInfo,
  LedgerEntry,
  TrustBundleInfo,
  WorkbenchModeState,
} from "./types"

export async function runTier0(): Promise<EvidenceBundle> {
  return await invoke<EvidenceBundle>("run_tier0")
}

export async function runVectors(): Promise<EvidenceBundle> {
  return await invoke<EvidenceBundle>("run_vectors")
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
  return await invoke<void>("open_path", { path })
}

export async function getAuthorityStatus(): Promise<AuthorityStatus> {
  return await invoke<AuthorityStatus>("get_authority_status")
}

export async function copyText(text: string): Promise<void> {
  await navigator.clipboard.writeText(text)
}

export async function runNeverlostCliAction(
  area: string,
  action: string,
  mode: "local" | "managed" = "local",
  source: "workbench" | "tray" | "admin" | "cli" = "workbench",
): Promise<CliActionResult> {
  return await invoke<CliActionResult>("run_neverlost_cli_action", {
    area,
    action,
    mode,
    source,
  })
}
export async function getWorkbenchMode(): Promise<WorkbenchModeState> {
  return await invoke<WorkbenchModeState>("get_workbench_mode")
}

export async function setWorkbenchMode(mode: "local" | "managed"): Promise<WorkbenchModeState> {
  return await invoke<WorkbenchModeState>("set_workbench_mode", { mode })
}
