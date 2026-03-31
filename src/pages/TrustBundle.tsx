import { useEffect, useState } from "react"
import { copyText, getTrustBundleInfo, openPath, readFileText } from "../lib/api"
import type { FileTextResult, TrustBundleInfo } from "../lib/types"

export default function TrustBundle() {
  const [info, setInfo] = useState<TrustBundleInfo | null>(null)
  const [opened, setOpened] = useState<FileTextResult | null>(null)

  useEffect(() => {
    getTrustBundleInfo().then(setInfo)
  }, [])

  async function openRaw() {
    if (!info?.path) return
    setOpened(await readFileText(info.path))
  }

  return (
    <div style={{ padding: 24 }}>
      <h1 style={{ fontSize: 32, marginTop: 0 }}>Trust Bundle</h1>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginBottom: 16 }}>
        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
          <h2 style={{ marginTop: 0 }}>Expected Principal</h2>
          <div style={{ color: "#d4d4d8", wordBreak: "break-all" }}>
            {info?.expected_principal ?? ""}
          </div>
          <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
            <button onClick={() => copyText(info?.expected_principal ?? "")}>Copy Principal</button>
          </div>
        </section>

        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
          <h2 style={{ marginTop: 0 }}>Expected Namespaces</h2>
          <div style={{ display: "grid", gap: 8 }}>
            {(info?.expected_namespaces ?? []).map((x) => (
              <div
                key={x}
                style={{
                  border: "1px solid #3f3f46",
                  borderRadius: 12,
                  padding: 10,
                  color: "#d4d4d8",
                  wordBreak: "break-all",
                }}
              >
                {x}
              </div>
            ))}
          </div>
        </section>
      </div>

      <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
        <h2 style={{ marginTop: 0 }}>Canonical Trust Input</h2>
        <div style={{ marginBottom: 12, color: "#a1a1aa" }}>Path: {info?.path ?? ""}</div>
        <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
          <button onClick={openRaw}>Open Raw File</button>
          <button onClick={() => openPath(info?.path ?? "")}>Open In System</button>
          <button onClick={() => copyText(info?.path ?? "")}>Copy Path</button>
        </div>
        <pre style={{ whiteSpace: "pre-wrap", color: "#d4d4d8" }}>{info?.raw_json ?? ""}</pre>
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