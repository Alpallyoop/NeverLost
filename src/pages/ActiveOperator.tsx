import { useEffect, useState } from "react"
import { copyText, getAuthorityStatus } from "../lib/api"
import type { AuthorityStatus } from "../lib/types"

export default function ActiveOperator() {
  const [status, setStatus] = useState<AuthorityStatus | null>(null)

  useEffect(() => {
    getAuthorityStatus().then(setStatus)
  }, [])

  return (
    <div style={{ padding: 24 }}>
      <h1 style={{ fontSize: 32, marginTop: 0 }}>Active Operator</h1>

      <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
        <div>Status: {status?.active ? "ACTIVE" : "INACTIVE"}</div>
        <div>Principal: {status?.principal ?? ""}</div>
        <div>Session ID: {status?.session_id ?? ""}</div>
        <div>Started: {status?.started_utc ?? ""}</div>
        <div>Ended: {status?.ended_utc ?? ""}</div>

        <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
          <button onClick={() => copyText(status?.principal ?? "")}>Copy Principal</button>
          <button onClick={() => copyText(status?.session_id ?? "")}>Copy Session ID</button>
        </div>
      </section>
    </div>
  )
}