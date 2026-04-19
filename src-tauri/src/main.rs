#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;

use tauri::{
    menu::{MenuBuilder, MenuItemBuilder},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Emitter, Manager, WindowEvent,
};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            #[cfg(desktop)]
            {
                use tauri_plugin_autostart::MacosLauncher;

                app.handle().plugin(
                    tauri_plugin_autostart::init(
                        MacosLauncher::LaunchAgent,
                        Some(vec![]),
                    )
                )?;

                let open_item = MenuItemBuilder::new("Open NeverLost")
                    .id("open")
                    .build(app)?;
                let start_item = MenuItemBuilder::new("Start Authority")
                    .id("start")
                    .build(app)?;
                let confirm_item = MenuItemBuilder::new("Confirm Authority")
                    .id("confirm")
                    .build(app)?;
                let end_item = MenuItemBuilder::new("End Authority")
                    .id("end")
                    .build(app)?;
                let quit_item = MenuItemBuilder::new("Exit NeverLost")
                    .id("quit")
                    .build(app)?;

                let menu = MenuBuilder::new(app)
                    .items(&[
                        &open_item,
                        &start_item,
                        &confirm_item,
                        &end_item,
                        &quit_item,
                    ])
                    .build()?;

                let default_icon = app.default_window_icon().cloned();

                let _tray = TrayIconBuilder::new()
                    .icon(default_icon.unwrap())
                    .tooltip("NeverLost Workbench")
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
                            "start" => {
                                let _ = app.emit("tray_start_authority", ());
                            }
                            "confirm" => {
                                let _ = app.emit("tray_confirm_authority", ());
                            }
                            "end" => {
                                let _ = app.emit("tray_end_authority", ());
                            }
                            "quit" => {
                                std::process::exit(0);
                            }
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
            commands::start_authority,
            commands::confirm_authority,
            commands::end_authority,
        ])
        .run(tauri::generate_context!())
        .expect("failed to run NeverLost Workbench");
}

fn main() {
    run();
}