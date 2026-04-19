import { useEffect, useState } from "react"
import { getLatestWorkbenchRuns, openPath, readFileText, runTier0, runVectors } from "../lib/api"
import type { EvidenceBundle, FileTextResult, LatestRunInfo } from "../lib/types"

export default function Debug() {
  const [verification, setVerification] = useState<EvidenceBundle | null>(null)
  const [validation, setValidation] = useState<EvidenceBundle | null>(null)
  const [latest, setLatest] = useState<LatestRunInfo[]>([])
  const [opened, setOpened] = useState<FileTextResult | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    getLatestWorkbenchRuns().then(setLatest)
  }, [])

  async function handleVerification() {
    setBusy(true)
    try {
      const result = await runTier0()
      setVerification(result)
      setLatest(await getLatestWorkbenchRuns())
      setOpened(null)
    } finally {
      setBusy(false)
    }
  }

  async function handleValidation() {
    setBusy(true)
    try {
      const result = await runVectors()
      setValidation(result)
      setLatest(await getLatestWorkbenchRuns())
      setOpened(null)
    } finally {
      setBusy(false)
    }
  }

  async function openRaw(path: string | undefined) {
    if (!path) return
    setOpened(await readFileText(path))
  }

  const latestVerification = latest.find((x) => x.kind === "verification")
  const latestValidation = latest.find((x) => x.kind === "validation")

  return (
    <div style={{ padding: 24 }}>
      <h1 style={{ fontSize: 32, marginTop: 0 }}>Debug</h1>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginBottom: 16 }}>
        <button onClick={handleVerification} disabled={busy}>Run Debug Verification</button>
        <button onClick={handleValidation} disabled={busy}>Run Debug Validation</button>
      </div>

      <div style={{ display: "grid", gap: 16 }}>
        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
          <h2 style={{ marginTop: 0 }}>Latest Verification Run</h2>
          <div>Run ID: {verification?.run_id ?? latestVerification?.run_id ?? ""}</div>
          <div>Run Dir: {verification?.run_dir ?? latestVerification?.run_dir ?? ""}</div>
          <div>Stdout Path: {verification?.stdout_path ?? latestVerification?.stdout_path ?? ""}</div>
          <div>Stderr Path: {verification?.stderr_path ?? latestVerification?.stderr_path ?? ""}</div>
          <div>Sha256sums Path: {verification?.sha256sums_path ?? latestVerification?.sha256sums_path ?? ""}</div>
          <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
            <button onClick={() => openRaw(verification?.stdout_path ?? latestVerification?.stdout_path)}>Open Raw Stdout</button>
            <button onClick={() => openRaw(verification?.stderr_path ?? latestVerification?.stderr_path)}>Open Raw Stderr</button>
            <button onClick={() => openRaw(verification?.sha256sums_path ?? latestVerification?.sha256sums_path)}>Open Raw Sha256sums</button>
            <button onClick={() => openPath(verification?.run_dir ?? latestVerification?.run_dir ?? "")}>Open Run Folder</button>
          </div>
        </section>

        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
          <h2 style={{ marginTop: 0 }}>Latest Validation Run</h2>
          <div>Run ID: {validation?.run_id ?? latestValidation?.run_id ?? ""}</div>
          <div>Run Dir: {validation?.run_dir ?? latestValidation?.run_dir ?? ""}</div>
          <div>Stdout Path: {validation?.stdout_path ?? latestValidation?.stdout_path ?? ""}</div>
          <div>Stderr Path: {validation?.stderr_path ?? latestValidation?.stderr_path ?? ""}</div>
          <div>Sha256sums Path: {validation?.sha256sums_path ?? latestValidation?.sha256sums_path ?? ""}</div>
          <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
            <button onClick={() => openRaw(validation?.stdout_path ?? latestValidation?.stdout_path)}>Open Raw Stdout</button>
            <button onClick={() => openRaw(validation?.stderr_path ?? latestValidation?.stderr_path)}>Open Raw Stderr</button>
            <button onClick={() => openRaw(validation?.sha256sums_path ?? latestValidation?.sha256sums_path)}>Open Raw Sha256sums</button>
            <button onClick={() => openPath(validation?.run_dir ?? latestValidation?.run_dir ?? "")}>Open Run Folder</button>
          </div>
        </section>
      </div>

      {opened && (
        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16, marginTop: 16 }}>
          <h2 style={{ marginTop: 0 }}>Raw File</h2>
          <div style={{ marginBottom: 12, color: "#a1a1aa" }}>{opened.path}</div>
          <pre style={{ whiteSpace: "pre-wrap", color: "#d4d4d8" }}>{opened.text}</pre>
        </section>
      )}
    </div>
  )
}