import { useEffect, useState } from "react"
import {
  activateProfile,
  createProfile,
  getActiveProfile,
  getAuthorityStatus,
  listProfiles,
} from "../lib/api"
import type {
  ActiveProfileInfo,
  AuthorityStatus,
  ProfileInfo,
} from "../lib/types"

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

export default function Profiles() {
  const [active, setActive] = useState<ActiveProfileInfo | null>(null)
  const [authority, setAuthority] = useState<AuthorityStatus | null>(null)
  const [profiles, setProfiles] = useState<ProfileInfo[]>([])
  const [displayName, setDisplayName] = useState("")
  const [principal, setPrincipal] = useState("")
  const [role, setRole] = useState("operator")
  const [busy, setBusy] = useState(false)

  async function refresh() {
    const [a, p, s] = await Promise.all([
      getActiveProfile(),
      listProfiles(),
      getAuthorityStatus(),
    ])
    setActive(a)
    setProfiles(p)
    setAuthority(s)
  }

  useEffect(() => {
    refresh()
  }, [])

  async function handleCreate() {
    if (!displayName.trim() || !principal.trim()) return
    setBusy(true)
    try {
      await createProfile(displayName.trim(), principal.trim(), role)
      setDisplayName("")
      setPrincipal("")
      setRole("operator")
      await refresh()
    } finally {
      setBusy(false)
    }
  }

  async function handleActivate(profileId: string) {
    setBusy(true)
    try {
      await activateProfile(profileId)
      await refresh()
    } finally {
      setBusy(false)
    }
  }

  return (
    <div style={{ padding: 24, minWidth: 0 }}>
      <h1 style={{ fontSize: 32, marginTop: 0 }}>Profiles</h1>

      <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16, marginBottom: 16, minWidth: 0 }}>
        <h2 style={{ marginTop: 0 }}>Active Profile</h2>
        <div style={{ marginBottom: 12 }}>
          <SessionChip active={!!authority?.active} />
        </div>
        <div>Display Name: {active?.display_name ?? ""}</div>
        <div>Profile ID: {active?.profile_id ?? ""}</div>
        <div style={{ overflowWrap: "anywhere" }}>Principal: {active?.principal ?? ""}</div>
        <div>Role: {active?.role ?? ""}</div>
        <div style={{ overflowWrap: "anywhere" }}>Session ID: {authority?.session_id ?? ""}</div>
      </section>

      <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16, marginBottom: 16, minWidth: 0 }}>
        <h2 style={{ marginTop: 0 }}>Create Profile</h2>
        <div style={{ display: "grid", gap: 12, maxWidth: 640 }}>
          <input
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            placeholder="Display name"
            style={{ padding: 10, borderRadius: 10, border: "1px solid #3f3f46", background: "#0f0f11", color: "#fff" }}
          />
          <input
            value={principal}
            onChange={(e) => setPrincipal(e.target.value)}
            placeholder="Principal"
            style={{ padding: 10, borderRadius: 10, border: "1px solid #3f3f46", background: "#0f0f11", color: "#fff" }}
          />
          <select
            value={role}
            onChange={(e) => setRole(e.target.value)}
            style={{ padding: 10, borderRadius: 10, border: "1px solid #3f3f46", background: "#0f0f11", color: "#fff" }}
          >
            <option value="operator">operator</option>
            <option value="admin">admin</option>
          </select>
          <button onClick={handleCreate} disabled={busy}>Create + Activate Profile</button>
        </div>
      </section>

      <section style={{ border: "1px solid #27272a", borderRadius: 16, padding: 16, minWidth: 0 }}>
        <h2 style={{ marginTop: 0 }}>Directory</h2>

        <div style={{ display: "grid", gap: 12 }}>
          {profiles.map((p) => (
            <div
              key={p.profile_id}
              style={{
                border: "1px solid #3f3f46",
                borderRadius: 12,
                padding: 12,
                minWidth: 0,
              }}
            >
              <div style={{ fontWeight: 700 }}>{p.display_name}</div>
              <div>Profile ID: {p.profile_id}</div>
              <div style={{ overflowWrap: "anywhere" }}>Principal: {p.principal}</div>
              <div>Role: {p.role}</div>
              <div>Created: {p.created_utc}</div>
              <div>Active: {p.active ? "Yes" : "No"}</div>
              <div style={{ marginTop: 12 }}>
                <button onClick={() => handleActivate(p.profile_id)} disabled={busy || p.active}>
                  {p.active ? "Active Profile" : "Activate Profile"}
                </button>
              </div>
            </div>
          ))}
        </div>
      </section>
    </div>
  )
}
