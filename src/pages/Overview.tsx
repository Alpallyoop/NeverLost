import { useEffect, useMemo, useState } from "react"
import {
  getAllowedSignersInfo,
  getAuthorityStatus,
  getTrustBundleInfo,
} from "../lib/api"
import type {
  AllowedSignersInfo,
  AuthorityStatus,
  TrustBundleInfo,
} from "../lib/types"

function StatusCard(props: {
  title: string
  status: string
  detail: string
}) {
  return (
    <section
      style={{
        border: "1px solid #27272a",
        borderRadius: 16,
        padding: 16,
        background: "#0f0f11",
        minWidth: 0,
      }}
    >
      <div style={{ fontSize: 14, color: "#a1a1aa", marginBottom: 8 }}>{props.title}</div>
      <div style={{ fontSize: 20, fontWeight: 700, marginBottom: 6 }}>{props.status}</div>
      <div style={{ color: "#d4d4d8", wordBreak: "break-all" }}>{props.detail}</div>
    </section>
  )
}

function SessionChip(props: { active: boolean }) {
  return (
    <span
      style={{
        display: "inline-block",
        padding: "4px 10px",
        borderRadius: 999,
        border: "1px solid #3f3f46",
        background: props.active ? "#0f1a12" : "#18181b",
        color: props.active ? "#86efac" : "#a1a1aa",
        fontSize: 12,
        fontWeight: 700,
      }}
    >
      {props.active ? "SESSION ACTIVE" : "NO ACTIVE SESSION"}
    </span>
  )
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

export default function Overview() {
  const [authority, setAuthority] = useState<AuthorityStatus | null>(null)
  const [trust, setTrust] = useState<TrustBundleInfo | null>(null)
  const [signers, setSigners] = useState<AllowedSignersInfo | null>(null)
  const [nowMs, setNowMs] = useState<number>(Date.now())

  useEffect(() => {
    async function load() {
      const [a, t, s] = await Promise.all([
        getAuthorityStatus(),
        getTrustBundleInfo(),
        getAllowedSignersInfo(),
      ])
      setAuthority(a)
      setTrust(t)
      setSigners(s)
    }
    load()
  }, [])

  useEffect(() => {
    const id = window.setInterval(() => setNowMs(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [])

  const sessionDuration = useMemo(() => {
    const started = parseUtc(authority?.started_utc ?? "")
    if (started === null) return ""
    const ended = parseUtc(authority?.ended_utc ?? "")
    if (authority?.active) {
      return `Session active for ${humanDuration(nowMs - started)}`
    }
    if (ended !== null) {
      return `Session was active for ${humanDuration(ended - started)}`
    }
    return ""
  }, [authority, nowMs])

  return (
    <div style={{ padding: 24, minWidth: 0 }}>
      <h1 style={{ fontSize: 32, marginTop: 0 }}>NeverLost Workbench</h1>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 16, marginBottom: 16 }}>
        <StatusCard
          title="Authority Status"
          status={authority?.active ? "ACTIVE" : "INACTIVE"}
          detail={authority?.principal ?? ""}
        />
        <StatusCard
          title="Trust Bundle"
          status={trust ? "READY" : "Loading"}
          detail={trust?.expected_principal ?? ""}
        />
        <StatusCard
          title="Allowed Signers"
          status={signers ? "READY" : "Loading"}
          detail={signers?.sha256 ?? ""}
        />
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16, minWidth: 0 }}>
          <h2 style={{ marginTop: 0 }}>Current Session</h2>
          <div style={{ marginBottom: 12 }}>
            <SessionChip active={!!authority?.active} />
          </div>
          <div style={{ overflowWrap: "anywhere" }}>Principal: {authority?.principal ?? ""}</div>
          <div style={{ overflowWrap: "anywhere" }}>Session ID: {authority?.session_id ?? ""}</div>
          <div>Started: {authority?.started_utc ?? ""}</div>
          <div>Ended: {authority?.ended_utc ?? ""}</div>
          {sessionDuration ? <div style={{ marginTop: 12, fontWeight: 700 }}>{sessionDuration}</div> : null}
        </section>

        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16, minWidth: 0 }}>
          <h2 style={{ marginTop: 0 }}>Identity Summary</h2>
          <div>Expected Principal: {trust?.expected_principal ?? ""}</div>
          <div>Namespaces: {trust?.expected_namespaces?.length ?? 0}</div>
          <div>Allowed Signers SHA-256: {signers?.sha256 ?? ""}</div>
        </section>
      </div>
    </div>
  )
}