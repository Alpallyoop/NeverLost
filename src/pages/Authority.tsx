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
  AuthorityStatus,
  LedgerEntry,
} from "../lib/types"

type TimelineRow = {
  action: string
  utc: string
  principal: string
  sessionId: string
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
        })
      }
    } catch {
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

function parseUtc(value: string): number | null {
  if (!value) return null
  const ms = Date.parse(value)
  return Number.isNaN(ms) ? null : ms
}

function humanDuration(ms: number): string {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000))
  const h = Math.floor(totalSeconds / 3600)
  const m = Math.floor((totalSeconds % 3600) / 60)
  const s = totalSeconds % 60
  if (h > 0) return `${h}h ${m}m ${s}s`
  if (m > 0) return `${m}m ${s}s`
  return `${s}s`
}

export default function Authority() {
  const [status, setStatus] = useState<AuthorityStatus | null>(null)
  const [rows, setRows] = useState<LedgerEntry[]>([])
  const [busy, setBusy] = useState(false)
  const [nowMs, setNowMs] = useState<number>(Date.now())

  async function refresh() {
    const [s, r] = await Promise.all([
      getAuthorityStatus(),
      getReceiptLedger(),
    ])
    setStatus(s)
    setRows(r)
  }

  useEffect(() => {
    refresh()
  }, [])

  useEffect(() => {
    const id = window.setInterval(() => setNowMs(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [])

  async function handleStart() {
    setBusy(true)
    try {
      await startAuthority()
      await refresh()
    } finally {
      setBusy(false)
    }
  }

  async function handleConfirm() {
    setBusy(true)
    try {
      await confirmAuthority()
      await refresh()
    } finally {
      setBusy(false)
    }
  }

  async function handleEnd() {
    setBusy(true)
    try {
      await endAuthority()
      await refresh()
    } finally {
      setBusy(false)
    }
  }

  const timeline = useMemo(() => {
    const parsed = parseAuthorityRows(rows)
    if (!status?.session_id) return parsed
    return parsed.filter((x) => x.sessionId === status.session_id)
  }, [rows, status])

  const sessionDuration = useMemo(() => {
    const started = parseUtc(status?.started_utc ?? "")
    if (started === null) return ""
    const ended = parseUtc(status?.ended_utc ?? "")
    if (status?.active) {
      return `Session active for ${humanDuration(nowMs - started)}`
    }
    if (ended !== null) {
      return `Session was active for ${humanDuration(ended - started)}`
    }
    return ""
  }, [status, nowMs])

  return (
    <div style={{ padding: 24, minWidth: 0 }}>
      <h1 style={{ fontSize: 32, marginTop: 0 }}>Authority</h1>

      <div style={{ display: "flex", gap: 12, marginBottom: 16, flexWrap: "wrap" }}>
        <button onClick={handleStart} disabled={busy}>Start Authority</button>
        <button onClick={handleConfirm} disabled={busy}>Confirm Authority</button>
        <button onClick={handleEnd} disabled={busy}>End Authority</button>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginBottom: 16 }}>
        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16, minWidth: 0 }}>
          <h2 style={{ marginTop: 0 }}>Current Authority State</h2>
          <div>Status: {status?.active ? "ACTIVE" : "INACTIVE"}</div>
          <div style={{ overflowWrap: "anywhere" }}>Principal: {status?.principal ?? ""}</div>
          <div style={{ overflowWrap: "anywhere" }}>Session ID: {status?.session_id ?? ""}</div>
          <div>Started: {status?.started_utc ?? ""}</div>
          <div>Ended: {status?.ended_utc ?? ""}</div>

          <div style={{ display: "flex", gap: 8, marginTop: 12, flexWrap: "wrap" }}>
            <button onClick={() => copyText(status?.principal ?? "")}>Copy Principal</button>
            <button onClick={() => copyText(status?.session_id ?? "")}>Copy Session ID</button>
          </div>
        </section>

        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16, minWidth: 0 }}>
          <h2 style={{ marginTop: 0 }}>Session Summary</h2>
          <div>State: {status?.active ? "Open session" : "Closed session"}</div>
          <div>Current principal: {status?.principal ?? ""}</div>
          <div>Last known session: {status?.session_id ?? ""}</div>
          {sessionDuration ? <div style={{ marginTop: 12, fontWeight: 700 }}>{sessionDuration}</div> : null}
        </section>
      </div>

      <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16, minWidth: 0 }}>
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
                  minWidth: 0,
                }}
              >
                <div style={{ fontWeight: 700 }}>{friendlyAction(item.action)}</div>
                <div>UTC: {item.utc}</div>
                <div style={{ overflowWrap: "anywhere" }}>Principal: {item.principal}</div>
                <div style={{ overflowWrap: "anywhere" }}>Session ID: {item.sessionId}</div>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}