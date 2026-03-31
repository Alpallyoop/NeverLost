mod commands;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
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