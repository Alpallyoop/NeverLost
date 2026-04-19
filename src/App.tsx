import { useEffect, useState } from "react"
import { listen } from "@tauri-apps/api/event"
import Overview from "./pages/Overview"
import Authority from "./pages/Authority"
import TrustBundle from "./pages/TrustBundle"
import AllowedSigners from "./pages/AllowedSigners"
import Receipts from "./pages/Receipts"
import Settings from "./pages/Settings"
import { confirmAuthority, endAuthority, startAuthority } from "./lib/api"

type Page =
  | "overview"
  | "authority"
  | "trust"
  | "signers"
  | "receipts"
  | "settings"

const APP_VERSION = "v1.0.0"
const KEY_MANAGED_MODE = "neverlost.settings.managed_mode"

function readBool(key: string, fallback: boolean): boolean {
  const raw = localStorage.getItem(key)
  if (raw === null) return fallback
  return raw === "true"
}

export default function App() {
  const [page, setPage] = useState<Page>("overview")
  const [managedMode, setManagedMode] = useState(false)

  useEffect(() => {
    setManagedMode(readBool(KEY_MANAGED_MODE, false))
  }, [])

  useEffect(() => {
    let mounted = true

    const setup = async () => {
      const unlistenStart = await listen("tray_start_authority", async () => {
        if (!mounted) return
        try {
          await startAuthority()
        } catch (error) {
          console.error("tray_start_authority failed:", error)
        }
      })

      const unlistenConfirm = await listen("tray_confirm_authority", async () => {
        if (!mounted) return
        try {
          await confirmAuthority()
        } catch (error) {
          console.error("tray_confirm_authority failed:", error)
        }
      })

      const unlistenEnd = await listen("tray_end_authority", async () => {
        if (!mounted) return
        try {
          await endAuthority()
        } catch (error) {
          console.error("tray_end_authority failed:", error)
        }
      })

      return () => {
        unlistenStart()
        unlistenConfirm()
        unlistenEnd()
      }
    }

    let cleanup: null | (() => void) = null
    setup().then((fn) => {
      cleanup = fn ?? null
    })

    return () => {
      mounted = false
      if (cleanup) cleanup()
    }
  }, [])

  return (
    <div style={{ display: "grid", gridTemplateColumns: "240px 1fr", minHeight: "100vh" }}>
      <aside style={{ borderRight: "1px solid #27272a", padding: 16, background: "#0a0a0a" }}>
        <div style={{ fontSize: 24, fontWeight: 700, marginBottom: 16 }}>NeverLost</div>

        <div style={{ marginBottom: 16, padding: 12, border: "1px solid #27272a", borderRadius: 12 }}>
          <div style={{ fontSize: 12, color: "#a1a1aa", marginBottom: 6 }}>Workbench</div>
          <div style={{ fontWeight: 700 }}>Standalone Authority Instrument</div>
          <div style={{ fontSize: 12, color: "#a1a1aa", marginTop: 6 }}>{APP_VERSION}</div>
          {managedMode ? (
            <div style={{ marginTop: 8 }}>
              <span
                style={{
                  display: "inline-block",
                  padding: "4px 10px",
                  borderRadius: 999,
                  border: "1px solid #3f3f46",
                  background: "#0f1a12",
                  color: "#86efac",
                  fontSize: 12,
                  fontWeight: 700,
                }}
              >
                MANAGED MODE
              </span>
            </div>
          ) : null}
        </div>

        <div style={{ display: "grid", gap: 10 }}>
          <button onClick={() => setPage("overview")}>Overview</button>
          <button onClick={() => setPage("authority")}>Authority</button>
          <button onClick={() => setPage("trust")}>Trust</button>
          <button onClick={() => setPage("signers")}>Signers</button>
          <button onClick={() => setPage("receipts")}>Receipts</button>
          <button onClick={() => setPage("settings")}>Settings</button>
        </div>
      </aside>

      <main style={{ display: "grid", gridTemplateRows: "1fr auto", minHeight: "100vh", minWidth: 0 }}>
        <div style={{ minWidth: 0, overflow: "auto" }}>
          {page === "overview" && <Overview />}
          {page === "authority" && <Authority />}
          {page === "trust" && <TrustBundle />}
          {page === "signers" && <AllowedSigners />}
          {page === "receipts" && <Receipts />}
          {page === "settings" && <Settings />}
        </div>

        <footer
          style={{
            borderTop: "1px solid #27272a",
            padding: "10px 16px",
            color: "#a1a1aa",
            fontSize: 12,
            background: "#0a0a0a",
          }}
        >
          NeverLost Workbench {APP_VERSION} · Operator Authority Console
        </footer>
      </main>
    </div>
  )
}