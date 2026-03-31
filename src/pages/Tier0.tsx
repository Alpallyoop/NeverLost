import { useState } from "react"
import { runTier0, readFileText } from "../lib/api"
import type { EvidenceBundle, FileTextResult } from "../lib/types"

export default function Tier0() {
  const [result, setResult] = useState<EvidenceBundle | null>(null)
  const [opened, setOpened] = useState<FileTextResult | null>(null)
  const [busy, setBusy] = useState(false)

  async function handleRun() {
    setBusy(true)
    try {
      setResult(await runTier0())
      setOpened(null)
    } finally {
      setBusy(false)
    }
  }

  async function openRaw(path: string | undefined) {
    if (!path) return
    setOpened(await readFileText(path))
  }

  return (
    <div style={{ padding: 24 }}>
      <h1 style={{ fontSize: 32, marginTop: 0 }}>System Check</h1>
      <button onClick={handleRun} disabled={busy}>Run Full Verification</button>

      <div style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16, marginTop: 16 }}>
        <div>Status: {result?.ok ? "PASS" : "Not Run / Fail"}</div>
        <div>Result: {result?.ok ? "Verification Passed" : ""}</div>
        <div>Run ID: {result?.run_id ?? ""}</div>
        <div>Run Dir: {result?.run_dir ?? ""}</div>
      </div>

      <div
        style={{
          border: "1px solid #27272a",
          borderRadius: 16,
          padding: 16,
          marginTop: 16,
          display: "grid",
          gap: 12,
        }}
      >
        <h2 style={{ margin: 0 }}>Artifacts</h2>

        <div>
          <div>Stdout: {result?.stdout_path ?? ""}</div>
          <button onClick={() => openRaw(result?.stdout_path)}>Open Raw Stdout</button>
        </div>

        <div>
          <div>Stderr: {result?.stderr_path ?? ""}</div>
          <button onClick={() => openRaw(result?.stderr_path)}>Open Raw Stderr</button>
        </div>

        <div>
          <div>Sha256sums: {result?.sha256sums_path ?? ""}</div>
          <button onClick={() => openRaw(result?.sha256sums_path)}>Open Raw Sha256sums</button>
        </div>
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