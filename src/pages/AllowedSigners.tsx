import { useEffect, useState } from "react"
import { copyText, getAllowedSignersInfo, openPath, readFileText } from "../lib/api"
import type { AllowedSignersInfo, FileTextResult } from "../lib/types"

export default function AllowedSigners() {
  const [info, setInfo] = useState<AllowedSignersInfo | null>(null)
  const [opened, setOpened] = useState<FileTextResult | null>(null)

  useEffect(() => {
    getAllowedSignersInfo().then(setInfo)
  }, [])

  async function openRaw() {
    if (!info?.path) return
    setOpened(await readFileText(info.path))
  }

  return (
    <div style={{ padding: 24 }}>
      <h1 style={{ fontSize: 32, marginTop: 0 }}>Allowed Signers</h1>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginBottom: 16 }}>
        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
          <h2 style={{ marginTop: 0 }}>Derived Artifact</h2>
          <div style={{ color: "#a1a1aa", marginBottom: 8 }}>Path</div>
          <div style={{ color: "#d4d4d8", wordBreak: "break-all" }}>{info?.path ?? ""}</div>
          <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
            <button onClick={() => openPath(info?.path ?? "")}>Open In System</button>
            <button onClick={() => copyText(info?.path ?? "")}>Copy Path</button>
          </div>
        </section>

        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
          <h2 style={{ marginTop: 0 }}>Integrity</h2>
          <div style={{ color: "#a1a1aa", marginBottom: 8 }}>SHA-256</div>
          <div style={{ color: "#d4d4d8", wordBreak: "break-all" }}>{info?.sha256 ?? ""}</div>
          <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
            <button onClick={() => copyText(info?.sha256 ?? "")}>Copy SHA-256</button>
          </div>
        </section>
      </div>

      <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
        <h2 style={{ marginTop: 0 }}>Derived Contents</h2>
        <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
          <button onClick={openRaw}>Open Raw File</button>
          <button onClick={() => copyText(info?.text ?? "")}>Copy Contents</button>
        </div>
        <pre style={{ whiteSpace: "pre-wrap", color: "#d4d4d8" }}>{info?.text ?? ""}</pre>
      </section>

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