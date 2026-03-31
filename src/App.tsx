import { useState } from "react"
import Overview from "./pages/Overview"
import ActiveOperator from "./pages/ActiveOperator"
import Authority from "./pages/Authority"
import TrustBundle from "./pages/TrustBundle"
import AllowedSigners from "./pages/AllowedSigners"
import Receipts from "./pages/Receipts"
import Debug from "./pages/Debug"

type Page =
  | "overview"
  | "activeOperator"
  | "authority"
  | "trust"
  | "signers"
  | "receipts"
  | "debug"

const APP_VERSION = "v1.0.0"

export default function App() {
  const [page, setPage] = useState<Page>("overview")

  return (
    <div style={{ display: "grid", gridTemplateColumns: "240px 1fr", minHeight: "100vh" }}>
      <aside style={{ borderRight: "1px solid #27272a", padding: 20, background: "#0a0a0a" }}>
        <div style={{ fontSize: 24, fontWeight: 700, marginBottom: 20 }}>NeverLost</div>
        <div style={{ display: "grid", gap: 10 }}>
          <button onClick={() => setPage("overview")}>Overview</button>
          <button onClick={() => setPage("activeOperator")}>Active Operator</button>
          <button onClick={() => setPage("authority")}>Authority</button>
          <button onClick={() => setPage("trust")}>Trust Bundle</button>
          <button onClick={() => setPage("signers")}>Allowed Signers</button>
          <button onClick={() => setPage("receipts")}>Receipts</button>
          <button onClick={() => setPage("debug")}>Debug</button>
        </div>

        <div style={{ marginTop: 24, paddingTop: 16, borderTop: "1px solid #27272a", color: "#a1a1aa", fontSize: 12 }}>
          <div>NeverLost Workbench</div>
          <div>{APP_VERSION}</div>
          <div>Standalone Authority Instrument</div>
        </div>
      </aside>

      <main style={{ display: "grid", gridTemplateRows: "1fr auto", minHeight: "100vh" }}>
        <div>
          {page === "overview" && <Overview />}
          {page === "activeOperator" && <ActiveOperator />}
          {page === "authority" && <Authority />}
          {page === "trust" && <TrustBundle />}
          {page === "signers" && <AllowedSigners />}
          {page === "receipts" && <Receipts />}
          {page === "debug" && <Debug />}
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