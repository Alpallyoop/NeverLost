import { useEffect, useMemo, useState } from "react"
import {
  confirmAuthority,
  copyText,
  endAuthority,
  getAuthorityStatus,
  getReceiptLedger,
  startAuthority,
} from "../lib/api"
import type {
  AuthorityActionResult,
  AuthorityStatus,
  LedgerEntry,
} from "../lib/types"

type TimelineRow = {
  action: string
  utc: string
  principal: string
  sessionId: string
  raw: string
}

function parseAuthorityRows(rows: LedgerEntry[]): TimelineRow[] {
  const parsed: TimelineRow[] = []

  for (const row of rows) {
    try {
      const obj = JSON.parse(row.raw)
      const action = String(obj.action ?? "")
      if (
        action === "authority.started" ||
        action === "authority.confirmed" ||
        action === "authority.ended"
      ) {
        parsed.push({
          action,
          utc: String(obj.time_utc ?? ""),
          principal: String(obj.principal ?? ""),
          sessionId: String(obj.session_id ?? ""),
          raw: row.raw,
        })
      }
    } catch {
      // ignore non-json lines
    }
  }

  return parsed
}

function friendlyAction(action: string): string {
  if (action === "authority.started") return "Authority Started"
  if (action === "authority.confirmed") return "Authority Confirmed"
  if (action === "authority.ended") return "Authority Ended"
  return action
}

export default function Authority() {
  const [status, setStatus] = useState<AuthorityStatus | null>(null)
  const [lastAction, setLastAction] = useState<AuthorityActionResult | null>(null)
  const [rows, setRows] = useState<LedgerEntry[]>([])
  const [busy, setBusy] = useState(false)

  async function refresh() {
    setStatus(await getAuthorityStatus())
    setRows(await getReceiptLedger())
  }

  useEffect(() => {
    refresh()
  }, [])

  async function handleStart() {
    setBusy(true)
    try {
      setLastAction(await startAuthority())
      await refresh()
    } finally {
      setBusy(false)
    }
  }

  async function handleConfirm() {
    setBusy(true)
    try {
      setLastAction(await confirmAuthority())
      await refresh()
    } finally {
      setBusy(false)
    }
  }

  async function handleEnd() {
    setBusy(true)
    try {
      setLastAction(await endAuthority())
      await refresh()
    } finally {
      setBusy(false)
    }
  }

  const timeline = useMemo(() => {
    const parsed = parseAuthorityRows(rows)
    if (!status?.session_id) return parsed.slice(0, 10)
    return parsed.filter((x) => x.sessionId === status.session_id)
  }, [rows, status])

  const latestActionUtc = timeline.length > 0 ? timeline[0].utc : ""

  return (
    <div style={{ padding: 24 }}>
      <h1 style={{ fontSize: 32, marginTop: 0 }}>Authority</h1>

      <div style={{ display: "flex", gap: 12, marginBottom: 16 }}>
        <button onClick={handleStart} disabled={busy}>Start Authority</button>
        <button onClick={handleConfirm} disabled={busy}>Confirm Authority</button>
        <button onClick={handleEnd} disabled={busy}>End Authority</button>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginBottom: 16 }}>
        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
          <h2 style={{ marginTop: 0 }}>Current Authority State</h2>
          <div>Status: {status?.active ? "ACTIVE" : "INACTIVE"}</div>
          <div>Principal: {status?.principal ?? ""}</div>
          <div>Session ID: {status?.session_id ?? ""}</div>
          <div>Started: {status?.started_utc ?? ""}</div>
          <div>Ended: {status?.ended_utc ?? ""}</div>
          <div>Latest Action Time: {latestActionUtc}</div>

          <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
            <button onClick={() => copyText(status?.principal ?? "")}>Copy Principal</button>
            <button onClick={() => copyText(status?.session_id ?? "")}>Copy Session ID</button>
          </div>
        </section>

        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
          <h2 style={{ marginTop: 0 }}>Last Action</h2>
          <div>Action: {lastAction?.action ?? ""}</div>
          <div>Session ID: {lastAction?.session_id ?? ""}</div>
          <div style={{ color: "#a1a1aa", marginTop: 12 }}>
            This section reflects the most recent authority action performed in the workbench.
          </div>
        </section>
      </div>

      <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
        <h2 style={{ marginTop: 0 }}>Authority Timeline</h2>

        {timeline.length === 0 ? (
          <div style={{ color: "#a1a1aa" }}>No authority lifecycle receipts found.</div>
        ) : (
          <div style={{ display: "grid", gap: 12 }}>
            {timeline.map((item, i) => (
              <div
                key={i}
                style={{
                  border: "1px solid #3f3f46",
                  borderRadius: 12,
                  padding: 12,
                }}
              >
                <div style={{ fontWeight: 700 }}>{friendlyAction(item.action)}</div>
                <div>UTC: {item.utc}</div>
                <div>Principal: {item.principal}</div>
                <div style={{ wordBreak: "break-all" }}>Session ID: {item.sessionId}</div>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}