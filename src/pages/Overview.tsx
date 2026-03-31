import { useEffect, useState } from "react"
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
      }}
    >
      <div style={{ fontSize: 14, color: "#a1a1aa", marginBottom: 8 }}>{props.title}</div>
      <div style={{ fontSize: 20, fontWeight: 700, marginBottom: 6 }}>{props.status}</div>
      <div style={{ color: "#d4d4d8", wordBreak: "break-word" }}>{props.detail}</div>
    </section>
  )
}

export default function Overview() {
  const [authority, setAuthority] = useState<AuthorityStatus | null>(null)
  const [trust, setTrust] = useState<TrustBundleInfo | null>(null)
  const [signers, setSigners] = useState<AllowedSignersInfo | null>(null)

  useEffect(() => {
    getAuthorityStatus().then(setAuthority)
    getTrustBundleInfo().then(setTrust)
    getAllowedSignersInfo().then(setSigners)
  }, [])

  return (
    <div style={{ padding: 24 }}>
      <h1 style={{ fontSize: 32, marginTop: 0 }}>NeverLost Workbench</h1>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 1fr 1fr 1fr",
          gap: 16,
          marginBottom: 16,
        }}
      >
        <StatusCard
          title="Authority Status"
          status={authority?.active ? "ACTIVE" : "INACTIVE"}
          detail={authority?.principal ?? ""}
        />
        <StatusCard
          title="Session ID"
          status={authority?.session_id ? "SET" : "NONE"}
          detail={authority?.session_id ?? ""}
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
        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
          <h2 style={{ marginTop: 0 }}>Active Operator</h2>
          <div>Status: {authority?.active ? "ACTIVE" : "INACTIVE"}</div>
          <div>Principal: {authority?.principal ?? ""}</div>
          <div>Session ID: {authority?.session_id ?? ""}</div>
        </section>

        <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16 }}>
          <h2 style={{ marginTop: 0 }}>Authority Timing</h2>
          <div>Started: {authority?.started_utc ?? ""}</div>
          <div>Ended: {authority?.ended_utc ?? ""}</div>
        </section>
      </div>
    </div>
  )
}