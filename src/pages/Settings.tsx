import { useEffect, useState } from "react"
import { disable as disableRunOnStartup, enable as enableRunOnStartup, isEnabled as isRunOnStartupEnabled } from "@tauri-apps/plugin-autostart"
import {
  getAllowedSignersInfo,
  getLatestWorkbenchRuns,
  getTrustBundleInfo,
  openPath,
  runTier0,
} from "../lib/api"
import type {
  AllowedSignersInfo,
  EvidenceBundle,
  LatestRunInfo,
  TrustBundleInfo,
} from "../lib/types"

const KEY_LAUNCH_HIDDEN = "neverlost.settings.launch_hidden"
const KEY_MANAGED_MODE = "neverlost.settings.managed_mode"
const KEY_TRAY_REOPEN = "neverlost.settings.tray_reopen_on_click"
const KEY_AUTO_START_AUTHORITY = "neverlost.settings.auto_start_authority"

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

function readBool(key: string, fallback: boolean): boolean {
  const raw = localStorage.getItem(key)
  if (raw === null) return fallback
  return raw === "true"
}

function writeBool(key: string, value: boolean) {
  localStorage.setItem(key, value ? "true" : "false")
}

export default function Settings() {
  const [runOnStartup, setRunOnStartup] = useState(false)
  const [launchHidden, setLaunchHidden] = useState(true)
  const [managedMode, setManagedMode] = useState(false)
  const [trayReopen, setTrayReopen] = useState(true)
  const [autoStartAuthority, setAutoStartAuthority] = useState(false)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState("")
  const [trust, setTrust] = useState<TrustBundleInfo | null>(null)
  const [signers, setSigners] = useState<AllowedSignersInfo | null>(null)
  const [latestRuns, setLatestRuns] = useState<LatestRunInfo[]>([])
  const [verifyBundle, setVerifyBundle] = useState<EvidenceBundle | null>(null)

  useEffect(() => {
    async function load() {
      const [startup, t, s, runs] = await Promise.all([
        isRunOnStartupEnabled(),
        getTrustBundleInfo(),
        getAllowedSignersInfo(),
        getLatestWorkbenchRuns(),
      ])
      setRunOnStartup(startup)
      setLaunchHidden(readBool(KEY_LAUNCH_HIDDEN, true))
      setManagedMode(readBool(KEY_MANAGED_MODE, false))
      setTrayReopen(readBool(KEY_TRAY_REOPEN, true))
      setAutoStartAuthority(readBool(KEY_AUTO_START_AUTHORITY, false))
      setTrust(t)
      setSigners(s)
      setLatestRuns(runs)
    }
    load()
  }, [])

  async function handleRunOnStartupToggle() {
    setBusy(true)
    setMessage("")
    try {
      if (runOnStartup) {
        await disableRunOnStartup()
        setRunOnStartup(false)
        setMessage("Run on startup disabled.")
      } else {
        await enableRunOnStartup()
        setRunOnStartup(true)
        setMessage("Run on startup enabled.")
      }
    } finally {
      setBusy(false)
    }
  }

  function handleLaunchHiddenToggle() {
    const next = !launchHidden
    setLaunchHidden(next)
    writeBool(KEY_LAUNCH_HIDDEN, next)
    setMessage(next ? "Launch hidden enabled. Next launch starts to tray." : "Launch hidden disabled. Next launch opens the window.")
  }

  function handleManagedModeToggle() {
    const next = !managedMode
    setManagedMode(next)
    writeBool(KEY_MANAGED_MODE, next)
    setMessage(next ? "Managed mode label enabled." : "Managed mode label disabled.")
  }

  function handleTrayReopenToggle() {
    const next = !trayReopen
    setTrayReopen(next)
    writeBool(KEY_TRAY_REOPEN, next)
    setMessage(next ? "Tray reopen preference saved." : "Tray reopen preference disabled.")
  }

  function handleAutoStartAuthorityToggle() {
    const next = !autoStartAuthority
    setAutoStartAuthority(next)
    writeBool(KEY_AUTO_START_AUTHORITY, next)
    setMessage(next ? "Auto-start authority enabled. Next launch will open a session if inactive." : "Auto-start authority disabled.")
  }

  async function handleVerifyIntegrity() {
    setBusy(true)
    setMessage("")
    try {
      const result = await runTier0()
      setVerifyBundle(result)
      setMessage(result.ok ? "Integrity verification passed." : "Integrity verification completed with issues.")
    } finally {
      setBusy(false)
    }
  }

  const latestVerification = latestRuns.find((x) => x.kind === "verification")

  return (
    <div style={{ padding: 24, minWidth: 0 }}>
      <h1 style={{ fontSize: 32, marginTop: 0 }}>Settings</h1>

      <div style={{ display: "grid", gap: 16 }}>
        <Card title="Startup">
          <div style={{ display: "grid", gap: 12 }}>
            <div>
              <div style={{ fontWeight: 700 }}>Run on system startup</div>
              <div style={{ color: "#a1a1aa", fontSize: 14 }}>Start NeverLost when this user signs in.</div>
              <div style={{ marginTop: 8 }}>
                <button onClick={handleRunOnStartupToggle} disabled={busy}>
                  {runOnStartup ? "Disable Run on Startup" : "Enable Run on Startup"}
                </button>
              </div>
            </div>

            <div>
              <div style={{ fontWeight: 700 }}>Launch hidden</div>
              <div style={{ color: "#a1a1aa", fontSize: 14 }}>This now controls real startup behavior on next launch.</div>
              <div style={{ marginTop: 8 }}>
                <button onClick={handleLaunchHiddenToggle}>
                  {launchHidden ? "Disable Launch Hidden" : "Enable Launch Hidden"}
                </button>
              </div>
            </div>

            <div>
              <div style={{ fontWeight: 700 }}>Auto-start authority</div>
              <div style={{ color: "#a1a1aa", fontSize: 14 }}>This now starts authority on launch when enabled and inactive.</div>
              <div style={{ marginTop: 8 }}>
                <button onClick={handleAutoStartAuthorityToggle}>
                  {autoStartAuthority ? "Disable Auto-start Authority" : "Enable Auto-start Authority"}
                </button>
              </div>
            </div>
          </div>
        </Card>

        <Card title="Tray">
          <div style={{ display: "grid", gap: 12 }}>
            <div>
              <div style={{ fontWeight: 700 }}>Tray click reopens window</div>
              <div style={{ color: "#a1a1aa", fontSize: 14 }}>Kept as the primary way back into the workbench.</div>
              <div style={{ marginTop: 8 }}>
                <button onClick={handleTrayReopenToggle}>
                  {trayReopen ? "Disable Tray Reopen" : "Enable Tray Reopen"}
                </button>
              </div>
            </div>
          </div>
        </Card>

        <Card title="Managed Mode">
          <div style={{ display: "grid", gap: 12 }}>
            <div>
              <div style={{ fontWeight: 700 }}>Managed deployment label</div>
              <div style={{ color: "#a1a1aa", fontSize: 14 }}>
                Marks this workbench as part of a managed environment. This is a UI/device mode flag, not enforcement.
              </div>
              <div style={{ marginTop: 8 }}>
                <button onClick={handleManagedModeToggle}>
                  {managedMode ? "Disable Managed Mode" : "Enable Managed Mode"}
                </button>
              </div>
            </div>

            <div style={{ color: "#d4d4d8", fontSize: 14 }}>
              Managed mode today is lightweight. Hard enforcement, cross-node administration, and non-stoppable service policy belong in later runtime/service layers.
            </div>
          </div>
        </Card>

        <Card title="Proofs">
          <div style={{ display: "grid", gap: 12 }}>
            <div>
              <div style={{ fontWeight: 700 }}>Verify Integrity</div>
              <div style={{ color: "#a1a1aa", fontSize: 14 }}>Run the current verification lane and store a fresh workbench run.</div>
              <div style={{ marginTop: 8 }}>
                <button onClick={handleVerifyIntegrity} disabled={busy}>Verify Integrity</button>
              </div>
            </div>

            <div>
              <div style={{ fontWeight: 700 }}>Open Trust Bundle</div>
              <div style={{ marginTop: 8 }}>
                <button onClick={() => openPath(trust?.path ?? "")}>Open Trust Bundle</button>
              </div>
            </div>

            <div>
              <div style={{ fontWeight: 700 }}>Open Allowed Signers</div>
              <div style={{ marginTop: 8 }}>
                <button onClick={() => openPath(signers?.path ?? "")}>Open Allowed Signers</button>
              </div>
            </div>

            <div>
              <div style={{ fontWeight: 700 }}>Latest Verification Run</div>
              <div style={{ color: "#a1a1aa", fontSize: 14, overflowWrap: "anywhere" }}>
                {verifyBundle?.run_dir ?? latestVerification?.run_dir ?? "No verification run found."}
              </div>
              {(verifyBundle?.run_dir || latestVerification?.run_dir) ? (
                <div style={{ marginTop: 8 }}>
                  <button onClick={() => openPath(verifyBundle?.run_dir ?? latestVerification?.run_dir ?? "")}>
                    Open Latest Verification Run
                  </button>
                </div>
              ) : null}
            </div>
          </div>
        </Card>

        <Card title="Current Values">
          <div>Run on startup: {runOnStartup ? "Enabled" : "Disabled"}</div>
          <div>Launch hidden: {launchHidden ? "Enabled" : "Disabled"}</div>
          <div>Auto-start authority: {autoStartAuthority ? "Enabled" : "Disabled"}</div>
          <div>Tray reopen on click: {trayReopen ? "Enabled" : "Disabled"}</div>
          <div>Managed mode: {managedMode ? "Enabled" : "Disabled"}</div>
        </Card>

        {message ? <div style={{ color: "#86efac", fontSize: 14 }}>{message}</div> : null}
      </div>
    </div>
  )
}