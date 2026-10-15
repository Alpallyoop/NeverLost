#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;

use tauri::{
    menu::{Menu, MenuBuilder, MenuItemBuilder},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Listener, Manager, WindowEvent,
};

fn repo_root_from_cwd() -> Option<std::path::PathBuf> {
    // Same resolution as the commands (NEVERLOST_ROOT, cwd ancestry, executable ancestry), so the tray
    // shows the real authority state when the installed app is started outside the repository.
    commands::repo_root().ok()
}

fn authority_state_from_disk() -> (bool, String, String, String) {
    let repo_root = match repo_root_from_cwd() {
        Some(v) => v,
        None => return (false, "".into(), "".into(), "".into()),
    };

    let path = repo_root.join("proofs").join("receipts").join("active_authority_session.json");
    if !path.exists() {
        return (false, "".into(), "".into(), "".into());
    }

    let raw = match std::fs::read_to_string(path) {
        Ok(v) => v,
        Err(_) => return (false, "".into(), "".into(), "".into()),
    };

    let parsed: serde_json::Value = match serde_json::from_str(&raw) {
        Ok(v) => v,
        Err(_) => return (false, "".into(), "".into(), "".into()),
    };

    let principal = parsed.get("principal").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let session_id = parsed.get("session_id").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let ended_utc = parsed.get("ended_utc").and_then(|v| v.as_str()).unwrap_or("").to_string();

    let active_bool = parsed.get("active").and_then(|v| v.as_bool()).unwrap_or(false);
    let state_active = parsed
        .get("authority_state")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .eq_ignore_ascii_case("active");
    let inferred_active = !session_id.is_empty() && ended_utc.trim().is_empty();

    (active_bool || state_active || inferred_active, principal, session_id, ended_utc)
}

fn current_workbench_mode_from_disk() -> String {
    let repo_root = match repo_root_from_cwd() {
        Some(v) => v,
        None => return "LOCAL".into(),
    };

    let path = repo_root.join("proofs").join("receipts").join("workbench_mode.json");
    if !path.exists() {
        return "LOCAL".into();
    }

    let raw = match std::fs::read_to_string(path) {
        Ok(v) => v,
        Err(_) => return "LOCAL".into(),
    };

    let parsed: serde_json::Value = match serde_json::from_str(&raw) {
        Ok(v) => v,
        Err(_) => return "LOCAL".into(),
    };

    if parsed.get("mode").and_then(|v| v.as_str()).unwrap_or("local") == "managed" {
        "MANAGED".into()
    } else {
        "LOCAL".into()
    }
}

fn emit_refresh(app: &AppHandle) {
    refresh_tray(app);
    let _ = app.emit("neverlost_authority_changed", ());
}

fn run_tray_action(app: &AppHandle, action: &str, mode: Option<&str>) {
    let final_mode = mode
        .map(|x| x.to_string())
        .unwrap_or_else(|| current_workbench_mode_from_disk().to_lowercase());

    let _ = commands::run_neverlost_cli_action(
        "authority".to_string(),
        action.to_string(),
        Some(final_mode),
        Some("tray".to_string()),
    );

    emit_refresh(app);
}

fn build_stateful_menu(app: &AppHandle) -> Result<(Menu<tauri::Wry>, String), String> {
    let (active, _principal, session_id, _ended_utc) = authority_state_from_disk();
    let mode = current_workbench_mode_from_disk();

    let status_text = if active {
        let short = if session_id.len() > 12 { &session_id[..12] } else { &session_id };
        format!("NeverLost - {} / ACTIVE ({})", mode, short)
    } else {
        format!("NeverLost - {} / INACTIVE", mode)
    };

    let status_item = MenuItemBuilder::new(status_text).id("status").enabled(false).build(app).map_err(|e| e.to_string())?;
    let open_item = MenuItemBuilder::new("Open NeverLost").id("open").build(app).map_err(|e| e.to_string())?;
    let start_local = MenuItemBuilder::new("Start LOCAL Session").id("start_local").build(app).map_err(|e| e.to_string())?;
    let start_managed = MenuItemBuilder::new("Start MANAGED Session").id("start_managed").build(app).map_err(|e| e.to_string())?;
    let confirm_item = MenuItemBuilder::new("Confirm Current Session").id("confirm").build(app).map_err(|e| e.to_string())?;
    let end_item = MenuItemBuilder::new("End Current Session").id("end").build(app).map_err(|e| e.to_string())?;
    let quit_item = MenuItemBuilder::new("Exit NeverLost").id("quit").build(app).map_err(|e| e.to_string())?;

    let menu = if active {
        MenuBuilder::new(app)
            .items(&[&status_item, &open_item, &confirm_item, &end_item, &quit_item])
            .build()
            .map_err(|e| e.to_string())?
    } else {
        MenuBuilder::new(app)
            .items(&[&status_item, &open_item, &start_local, &start_managed, &quit_item])
            .build()
            .map_err(|e| e.to_string())?
    };

    let tooltip = if active {
        format!("NeverLost ({} / ACTIVE)", mode)
    } else {
        format!("NeverLost ({} / INACTIVE)", mode)
    };

    Ok((menu, tooltip))
}

fn refresh_tray(app: &AppHandle) {
    if let Some(tray) = app.tray_by_id("neverlost-stateful") {
        if let Ok((menu, tooltip)) = build_stateful_menu(app) {
            let _ = tray.set_menu(Some(menu));
            let _ = tray.set_tooltip(Some(tooltip));
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            #[cfg(desktop)]
            {
                use tauri_plugin_autostart::MacosLauncher;

                app.handle().plugin(
                    tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, Some(vec![]))
                )?;

                let (menu, tooltip) = build_stateful_menu(&app.handle())?;
                let icon = app.default_window_icon().cloned().ok_or("TRAY_ICON_MISSING")?;

                let _tray = TrayIconBuilder::with_id("neverlost-stateful")
                    .icon(icon)
                    .tooltip(&tooltip)
                    .menu(&menu)
                    .show_menu_on_left_click(false)
                    .on_menu_event(|app, event| {
                        match event.id.as_ref() {
                            "open" => {
                                if let Some(window) = app.get_webview_window("main") {
                                    let _ = window.set_skip_taskbar(false);
                                    let _ = window.show();
                                    let _ = window.set_focus();
                                }
                            }
                            "start_local" => {
                                let _ = commands::set_workbench_mode("local".to_string());
                                run_tray_action(app, "start", Some("local"));
                            }
                            "start_managed" => {
                                let _ = commands::set_workbench_mode("managed".to_string());
                                run_tray_action(app, "start", Some("managed"));
                            }
                            "confirm" => run_tray_action(app, "confirm", None),
                            "end" => run_tray_action(app, "end", None),
                            "quit" => std::process::exit(0),
                            _ => {}
                        }
                    })
                    .on_tray_icon_event(|tray, event| {
                        if let TrayIconEvent::Click {
                            button: MouseButton::Left,
                            button_state: MouseButtonState::Up,
                            ..
                        } = event
                        {
                            let app = tray.app_handle();
                            if let Some(window) = app.get_webview_window("main") {
                                let _ = window.set_skip_taskbar(false);
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                    })
                    .build(app)?;

                let app_handle = app.handle().clone();
                app.listen("rebuild_tray_now", move |_| {
                    refresh_tray(&app_handle);
                });
            }

            Ok(())
        })
        .on_window_event(|window, event| {
            if window.label() == "main" {
                if let WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let _ = window.hide();
                    let _ = window.set_skip_taskbar(true);
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            commands::run_tier0,
            commands::run_vectors,
            commands::get_receipt_ledger,
            commands::read_file_text,
            commands::get_trust_bundle_info,
            commands::get_allowed_signers_info,
            commands::get_latest_workbench_runs,
            commands::open_path,
            commands::get_authority_status,
            commands::run_neverlost_cli_action,
            commands::get_workbench_mode,
            commands::set_workbench_mode,
        ])
        .run(tauri::generate_context!())
        .expect("failed to run NeverLost Workbench");
}

fn main() {
    run();
}
