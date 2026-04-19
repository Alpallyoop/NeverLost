import React from "react"
import ReactDOM from "react-dom/client"
import App from "./App"
import "./index.css"
import { getAuthorityStatus, startAuthority } from "./lib/api"
import { getCurrentWindow } from "@tauri-apps/api/window"

const KEY_AUTO_START_AUTHORITY = "neverlost.settings.auto_start_authority"
const KEY_LAUNCH_HIDDEN = "neverlost.settings.launch_hidden"

function readBool(key: string, fallback: boolean): boolean {
  const raw = localStorage.getItem(key)
  if (raw === null) return fallback
  return raw === "true"
}

async function bootstrapNeverLost() {
  try {
    const appWindow = getCurrentWindow()

    const launchHidden = readBool(KEY_LAUNCH_HIDDEN, true)
    if (launchHidden) {
      await appWindow.hide()
      await appWindow.setSkipTaskbar(true)
    } else {
      await appWindow.show()
      await appWindow.setSkipTaskbar(false)
      await appWindow.setFocus()
    }

    const autoStartAuthority = readBool(KEY_AUTO_START_AUTHORITY, false)
    if (autoStartAuthority) {
      const status = await getAuthorityStatus()
      if (!status.active) {
        await startAuthority()
      }
    }
  } catch (error) {
    console.error("NeverLost bootstrap failed:", error)
  }
}

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)

bootstrapNeverLost()