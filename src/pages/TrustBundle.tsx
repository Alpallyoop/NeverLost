import { useEffect, useMemo, useState } from "react"
import {
  copyText,
  getAllowedSignersInfo,
  getTrustBundleInfo,
  openPath,
} from "../lib/api"
import type {
  AllowedSignersInfo,
  TrustBundleInfo,
} from "../lib/types"

function Card(props: { title: string; children: React.ReactNode }) {
  return (
    <section
      style={{
        border: "1px solid #27272a",
        borderRadius: 16,
        padding: 16,
        minWidth: 0,
      }}
    >
      <h2 style={{ marginTop: 0 }}>{props.title}</h2>
      {props.children}
    </section>
  )
}

function StatusPill(props: { ok: boolean; text: string }) {
  return (
    <span
      style={{
        display: "inline-block",
        padding: "4px 10px",
        borderRadius: 999,
        border: "1px solid #3f3f46",
        background: props.ok ? "#0f1a12" : "#1a1010",
        color: props.ok ? "#86efac" : "#fca5a5",
        fontSize: 12,
        fontWeight: 700,
      }}
    >
      {props.text}
    </span>
  )
}

export default function TrustBundle() {
  const [trust, setTrust] = useState<TrustBundleInfo | null>(null)
  const [signers, setSigners] = useState<AllowedSignersInfo | null>(null)

  useEffect(() => {
    async function load() {
      const [t, s] = await Promise.all([
        getTrustBundleInfo(),
        getAllowedSignersInfo(),
      ])
      setTrust(t)
      setSigners(s)
    }
    load()
  }, [])

  const verification = useMemo(() => {
    const hasPrincipal = !!trust?.expected_principal
    const hasNamespaces = (trust?.expected_namespaces?.length ?? 0) > 0
    const hasTrustPath = !!trust?.path
    const hasSignersPath = !!signers?.path
    const hasSignerHash = !!signers?.sha256

    return [
      { ok: hasPrincipal, text: "Expected principal present" },
      { ok: hasNamespaces, text: "Namespaces present" },
      { ok: hasTrustPath, text: "Trust bundle present" },
      { ok: hasSignersPath, text: "Allowed signers present" },
      { ok: hasSignerHash, text: "Allowed signers hash present" },
    ]
  }, [trust, signers])

  return (
    <div style={{ padding: 24, minWidth: 0 }}>
      <h1 style={{ fontSize: 32, marginTop: 0 }}>Trust</h1>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginBottom: 16 }}>
        <Card title="Verification Status">
          <div style={{ display: "grid", gap: 10 }}>
            {verification.map((item, i) => (
              <div key={i}>
                <StatusPill ok={item.ok} text={item.ok ? "PASS" : "MISSING"} />{" "}
                <span style={{ marginLeft: 8 }}>{item.text}</span>
              </div>
            ))}
          </div>
        </Card>

        <Card title="Trust Summary">
          <div style={{ marginBottom: 10, fontWeight: 700 }}>Expected Principal</div>
          <div style={{ overflowWrap: "anywhere", marginBottom: 12 }}>{trust?.expected_principal ?? ""}</div>

          <div style={{ marginBottom: 10, fontWeight: 700 }}>Expected Namespaces</div>
          <div style={{ display: "grid", gap: 6, marginBottom: 12 }}>
            {(trust?.expected_namespaces ?? []).map((ns, i) => (
              <div key={i}>{ns}</div>
            ))}
          </div>

          <div style={{ marginBottom: 10, fontWeight: 700 }}>Allowed Signers SHA-256</div>
          <div style={{ overflowWrap: "anywhere" }}>{signers?.sha256 ?? ""}</div>
        </Card>
      </div>

      <div style={{ display: "grid", gap: 16 }}>
        <Card title="Trust Bundle">
          <div style={{ marginBottom: 8, fontWeight: 700 }}>Path</div>
          <div style={{ overflowWrap: "anywhere", marginBottom: 12 }}>{trust?.path ?? ""}</div>

          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 12 }}>
            <button onClick={() => copyText(trust?.expected_principal ?? "")}>Copy Principal</button>
            <button onClick={() => copyText(trust?.path ?? "")}>Copy Path</button>
            <button onClick={() => openPath(trust?.path ?? "")}>Open In System</button>
          </div>

          <details>
            <summary>Open Raw File</summary>
            <pre style={{ whiteSpace: "pre-wrap", color: "#d4d4d8", marginTop: 12, overflowWrap: "anywhere" }}>
              {trust?.raw_json ?? ""}
            </pre>
          </details>
        </Card>

        <Card title="Allowed Signers">
          <div style={{ marginBottom: 8, fontWeight: 700 }}>Path</div>
          <div style={{ overflowWrap: "anywhere", marginBottom: 12 }}>{signers?.path ?? ""}</div>

          <div style={{ marginBottom: 8, fontWeight: 700 }}>SHA-256</div>
          <div style={{ overflowWrap: "anywhere", marginBottom: 12 }}>{signers?.sha256 ?? ""}</div>

          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 12 }}>
            <button onClick={() => copyText(signers?.path ?? "")}>Copy Path</button>
            <button onClick={() => copyText(signers?.sha256 ?? "")}>Copy SHA-256</button>
            <button onClick={() => openPath(signers?.path ?? "")}>Open In System</button>
          </div>

          <details>
            <summary>Open Raw File</summary>
            <pre style={{ whiteSpace: "pre-wrap", color: "#d4d4d8", marginTop: 12, overflowWrap: "anywhere" }}>
              {signers?.text ?? ""}
            </pre>
          </details>
        </Card>
      </div>
    </div>
  )
}