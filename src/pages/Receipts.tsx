import { useEffect, useMemo, useState } from "react"
import { copyText, getReceiptLedger } from "../lib/api"
import type { LedgerEntry } from "../lib/types"

type ParsedRow = {
  raw: string
  action: string
  utc: string
  principal: string
  sessionId: string
}

type SessionGroup = {
  sessionId: string
  principal: string
  startedUtc: string
  endedUtc: string
  rows: ParsedRow[]
}

function tryParse(raw: string): ParsedRow {
  try {
    const obj = JSON.parse(raw)
    return {
      raw,
      action: String(obj.action ?? ""),
      utc: String(obj.time_utc ?? ""),
      principal: String(obj.principal ?? ""),
      sessionId: String(obj.session_id ?? ""),
    }
  } catch {
    return {
      raw,
      action: "",
      utc: "",
      principal: "",
      sessionId: "",
    }
  }
}

function friendlyAction(action: string): string {
  if (action === "authority.started") return "Authority Started"
  if (action === "authority.confirmed") return "Authority Confirmed"
  if (action === "authority.ended") return "Authority Ended"
  return action || "Receipt Entry"
}

function groupRows(rows: ParsedRow[]): SessionGroup[] {
  const map = new Map<string, SessionGroup>()

  for (const row of rows) {
    const key = row.sessionId || "no-session"
    const current = map.get(key)

    if (!current) {
      map.set(key, {
        sessionId: key,
        principal: row.principal,
        startedUtc: row.action === "authority.started" ? row.utc : "",
        endedUtc: row.action === "authority.ended" ? row.utc : "",
        rows: [row],
      })
    } else {
      current.rows.push(row)
      if (!current.principal && row.principal) current.principal = row.principal
      if (row.action === "authority.started" && !current.startedUtc) current.startedUtc = row.utc
      if (row.action === "authority.ended") current.endedUtc = row.utc
    }
  }

  const out = Array.from(map.values())
  for (const g of out) {
    g.rows.sort((a, b) => String(b.utc).localeCompare(String(a.utc)))
  }
  out.sort((a, b) => {
    const at = a.startedUtc || a.rows[0]?.utc || ""
    const bt = b.startedUtc || b.rows[0]?.utc || ""
    return String(bt).localeCompare(String(at))
  })

  return out
}

export default function Receipts() {
  const [rows, setRows] = useState<LedgerEntry[]>([])

  useEffect(() => {
    getReceiptLedger().then(setRows)
  }, [])

  const parsed = useMemo(() => rows.map((x) => tryParse(x.raw)), [rows])
  const groups = useMemo(() => groupRows(parsed), [parsed])

  return (
    <div style={{ padding: 24, minWidth: 0 }}>
      <h1 style={{ fontSize: 32, marginTop: 0 }}>Receipts</h1>

      {groups.length === 0 ? (
        <div style={{ color: "#a1a1aa" }}>No receipts found.</div>
      ) : (
        <div style={{ display: "grid", gap: 16 }}>
          {groups.map((group, index) => (
            <details
              key={group.sessionId}
              open={index === 0}
              style={{
                border: "1px solid #27272a",
                borderRadius: 16,
                padding: 16,
                minWidth: 0,
              }}
            >
              <summary style={{ cursor: "pointer", fontWeight: 700, wordBreak: "break-all" }}>
                Session {group.sessionId}
              </summary>

              <div style={{ marginTop: 12, marginBottom: 12 }}>
                <div style={{ overflowWrap: "anywhere" }}>Principal: {group.principal}</div>
                <div>Started: {group.startedUtc}</div>
                <div>Ended: {group.endedUtc}</div>
              </div>

              <div style={{ display: "grid", gap: 12 }}>
                {group.rows.map((row, i) => (
                  <div
                    key={i}
                    style={{
                      border: "1px solid #3f3f46",
                      borderRadius: 12,
                      padding: 12,
                      minWidth: 0,
                    }}
                  >
                    <div style={{ fontWeight: 700 }}>{friendlyAction(row.action)}</div>
                    <div>UTC: {row.utc}</div>
                    <div>Action: {row.action}</div>

                    <details style={{ marginTop: 12 }}>
                      <summary>Raw Receipt</summary>
                      <div style={{ marginTop: 12 }}>
                        <button onClick={() => copyText(row.raw)}>Copy Raw Receipt</button>
                      </div>
                      <pre style={{ whiteSpace: "pre-wrap", color: "#d4d4d8", marginTop: 12, overflowWrap: "anywhere" }}>
                        {row.raw}
                      </pre>
                    </details>
                  </div>
                ))}
              </div>
            </details>
          ))}
        </div>
      )}
    </div>
  )
}