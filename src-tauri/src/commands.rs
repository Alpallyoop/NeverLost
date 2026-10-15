use chrono::Utc;
use serde::Serialize;
use sha2::Digest;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// PowerShell host used for the canonical runners. Mirrors scripts/_lib_neverlost_host_v1.ps1:
/// NEVERLOST_PS_HOST override, then Windows PowerShell 5.1 on Windows, then `pwsh` elsewhere.
pub fn ps_host() -> String {
    if let Ok(v) = std::env::var("NEVERLOST_PS_HOST") {
        if !v.trim().is_empty() {
            return v;
        }
    }
    if cfg!(windows) {
        let windir = std::env::var("WINDIR").unwrap_or_else(|_| r"C:\Windows".to_string());
        return format!(r"{}\System32\WindowsPowerShell\v1.0\powershell.exe", windir);
    }
    "pwsh".to_string()
}

fn local_actor_id() -> String {
    std::env::var("USERNAME")
        .or_else(|_| std::env::var("USER"))
        .unwrap_or_else(|_| "local-operator".to_string())
}

#[derive(Serialize)]
pub struct EvidenceBundle {
    ok: bool,
    token: String,
    run_id: String,
    run_dir: String,
    stdout_path: String,
    stderr_path: String,
    sha256sums_path: String,
    stdout: String,
    stderr: String,
}

#[derive(Serialize)]
pub struct LedgerEntry {
    raw: String,
}

#[derive(Serialize)]
pub struct FileTextResult {
    ok: bool,
    path: String,
    text: String,
}

#[derive(Serialize)]
pub struct TrustBundleInfo {
    ok: bool,
    path: String,
    expected_principal: String,
    expected_namespaces: Vec<String>,
    raw_json: String,
}

#[derive(Serialize)]
pub struct AllowedSignersInfo {
    ok: bool,
    path: String,
    text: String,
    sha256: String,
}

#[derive(Serialize)]
pub struct LatestRunInfo {
    kind: String,
    run_id: String,
    run_dir: String,
    stdout_path: String,
    stderr_path: String,
    sha256sums_path: String,
}

#[derive(Serialize)]
pub struct AuthorityStatus {
    ok: bool,
    active: bool,
    principal: String,
    session_id: String,
    started_utc: String,
    ended_utc: String,
}

fn is_repo_root(path: &Path) -> bool {
    path.join("scripts").join("neverlost_cli_v1.ps1").exists()
}

fn search_repo_root_from(start: &Path) -> Option<PathBuf> {
    let mut dir = if start.is_file() {
        start.parent()?.to_path_buf()
    } else {
        start.to_path_buf()
    };

    for _ in 0..10 {
        if is_repo_root(&dir) {
            return Some(dir);
        }
        if !dir.pop() {
            break;
        }
    }

    None
}

pub fn repo_root() -> Result<PathBuf, String> {
    if let Ok(raw) = std::env::var("NEVERLOST_ROOT") {
        let candidate = PathBuf::from(raw);
        if is_repo_root(&candidate) {
            return candidate
                .canonicalize()
                .map_err(|e| format!("REPO_ROOT_CANONICALIZE_FAILED: {}", e));
        }
    }

    if let Ok(cwd) = std::env::current_dir() {
        if let Some(root) = search_repo_root_from(&cwd) {
            return root
                .canonicalize()
                .map_err(|e| format!("REPO_ROOT_CANONICALIZE_FAILED: {}", e));
        }
    }

    if let Ok(exe) = std::env::current_exe() {
        if let Some(root) = search_repo_root_from(&exe) {
            return root
                .canonicalize()
                .map_err(|e| format!("REPO_ROOT_CANONICALIZE_FAILED: {}", e));
        }
    }

    Err("NEVERLOST_REPO_ROOT_NOT_FOUND".to_string())
}

fn scripts_dir(root: &Path) -> PathBuf {
    root.join("scripts")
}

fn receipts_dir(root: &Path) -> PathBuf {
    root.join("proofs").join("receipts")
}

fn trust_dir(root: &Path) -> PathBuf {
    root.join("proofs").join("trust")
}

fn allowed_evidence_roots(root: &Path) -> Vec<PathBuf> {
    vec![receipts_dir(root), trust_dir(root)]
}

fn ensure_allowed_evidence_path(path: &Path) -> Result<PathBuf, String> {
    if !path.exists() {
        return Err(format!("FILE_MISSING: {}", path.display()));
    }

    let target = path
        .canonicalize()
        .map_err(|e| format!("PATH_CANONICALIZE_FAILED: {}", e))?;

    let root = repo_root()?;
    for allowed_root in allowed_evidence_roots(&root) {
        if allowed_root.exists() {
            let canonical_root = allowed_root
                .canonicalize()
                .map_err(|e| format!("ROOT_CANONICALIZE_FAILED: {}", e))?;

            if target == canonical_root || target.starts_with(&canonical_root) {
                return Ok(target);
            }
        }
    }

    Err(format!("PATH_OUTSIDE_EVIDENCE_ROOTS: {}", target.display()))
}

fn workbench_runs_dir(root: &Path) -> PathBuf {
    receipts_dir(root).join("workbench_runs")
}

fn active_authority_session_path(root: &Path) -> PathBuf {
    receipts_dir(root).join("active_authority_session.json")
}

fn utc_now() -> String {
    Utc::now().format("%Y%m%dT%H%M%SZ").to_string()
}

fn sha256_hex(path: &Path) -> Result<String, String> {
    let bytes = fs::read(path).map_err(|e| format!("HASH_READ_FAILED: {}", e))?;
    let mut h = sha2::Sha256::new();
    h.update(bytes);
    Ok(format!("{:x}", h.finalize()))
}

fn write_file(path: &Path, content: &str) -> Result<(), String> {
    fs::write(path, content).map_err(|e| format!("WRITE_FAIL: {}", e))
}

fn write_sha256sums(run_dir: &Path) -> Result<PathBuf, String> {
    let sha_path = run_dir.join("sha256sums.txt");
    let mut lines: Vec<String> = Vec::new();

    for name in ["stdout.txt", "stderr.txt"] {
        let p = run_dir.join(name);
        let sha = sha256_hex(&p)?;
        lines.push(format!("{} *{}", sha, name));
    }

    write_file(&sha_path, &(lines.join("\n") + "\n"))?;
    Ok(sha_path)
}

fn run_ps_script(script_name: &str, success_token: &str) -> Result<EvidenceBundle, String> {
    let root = repo_root()?;
    let run_id = utc_now();
    let run_dir = workbench_runs_dir(&root).join(&run_id);
    fs::create_dir_all(&run_dir).map_err(|e| format!("RUN_DIR_CREATE_FAILED: {}", e))?;

    let runner_path = scripts_dir(&root).join(script_name);
    if !runner_path.exists() {
        return Err(format!("RUNNER_MISSING: {}", runner_path.display()));
    }

    let output = Command::new(ps_host())
        .arg("-NoProfile")
        .arg("-NonInteractive")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-File")
        .arg(&runner_path)
        .arg("-RepoRoot")
        .arg(&root)
        .output()
        .map_err(|e| format!("PROCESS_START_FAILED: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).replace("\r\n", "\n");
    let stderr = String::from_utf8_lossy(&output.stderr).replace("\r\n", "\n");
    let ok = output.status.success() && stdout.contains(success_token);

    let stdout_path = run_dir.join("stdout.txt");
    let stderr_path = run_dir.join("stderr.txt");

    write_file(&stdout_path, &stdout)?;
    write_file(&stderr_path, &stderr)?;
    let sha_path = write_sha256sums(&run_dir)?;

    Ok(EvidenceBundle {
        ok,
        token: success_token.to_string(),
        run_id,
        run_dir: run_dir.display().to_string(),
        stdout_path: stdout_path.display().to_string(),
        stderr_path: stderr_path.display().to_string(),
        sha256sums_path: sha_path.display().to_string(),
        stdout,
        stderr,
    })
}

#[tauri::command]
pub fn run_tier0() -> Result<EvidenceBundle, String> {
    run_ps_script(
        "_RUN_neverlost_tier0_full_green_v1.ps1",
        "NEVERLOST_TIER0_FULL_GREEN",
    )
}

#[tauri::command]
pub fn run_vectors() -> Result<EvidenceBundle, String> {
    run_ps_script(
        "_RUN_neverlost_vectors_v3.ps1",
        "NEVERLOST_VECTORS_FULL_GREEN",
    )
}

#[tauri::command]
pub fn get_receipt_ledger() -> Result<Vec<LedgerEntry>, String> {
    let root = repo_root()?;
    let ledger_path = receipts_dir(&root).join("neverlost.ndjson");
    if !ledger_path.exists() {
        return Ok(vec![]);
    }

    let text =
        fs::read_to_string(&ledger_path).map_err(|e| format!("LEDGER_READ_FAILED: {}", e))?;

    let rows = text
        .lines()
        .filter(|x| !x.trim().is_empty())
        .rev()
        .take(50)
        .map(|line| LedgerEntry {
            raw: line.to_string(),
        })
        .collect();

    Ok(rows)
}

#[tauri::command]
pub fn read_file_text(path: String) -> Result<FileTextResult, String> {
    let pb = PathBuf::from(&path);
    let safe_path = ensure_allowed_evidence_path(&pb)?;

    let text = fs::read_to_string(&safe_path)
        .map_err(|e| format!("FILE_READ_FAILED: {}", e))?
        .replace("\r\n", "\n");

    Ok(FileTextResult {
        ok: true,
        path: safe_path.display().to_string(),
        text,
    })
}

#[tauri::command]
pub fn get_trust_bundle_info() -> Result<TrustBundleInfo, String> {
    let root = repo_root()?;
    let trust_root = trust_dir(&root);
    let path = trust_root.join("trust_bundle.json");
    let expected_principal_path = trust_root.join("expected_principal0.txt");
    let expected_namespaces_path = trust_root.join("expected_namespaces_principal0.txt");

    let raw_json = fs::read_to_string(&path)
        .map_err(|e| format!("TRUST_BUNDLE_READ_FAILED: {}", e))?
        .replace("\r\n", "\n");

    let expected_principal = fs::read_to_string(&expected_principal_path)
        .map_err(|e| format!("EXPECTED_PRINCIPAL_READ_FAILED: {}", e))?
        .lines()
        .next()
        .unwrap_or("")
        .trim()
        .to_string();

    let expected_namespaces = fs::read_to_string(&expected_namespaces_path)
        .map_err(|e| format!("EXPECTED_NAMESPACES_READ_FAILED: {}", e))?
        .lines()
        .map(|x| x.trim().to_string())
        .filter(|x| !x.is_empty())
        .collect();

    Ok(TrustBundleInfo {
        ok: true,
        path: path.display().to_string(),
        expected_principal,
        expected_namespaces,
        raw_json,
    })
}

#[tauri::command]
pub fn get_allowed_signers_info() -> Result<AllowedSignersInfo, String> {
    let root = repo_root()?;
    let path = trust_dir(&root).join("allowed_signers");
    let text = fs::read_to_string(&path)
        .map_err(|e| format!("ALLOWED_SIGNERS_READ_FAILED: {}", e))?
        .replace("\r\n", "\n");
    let sha256 = sha256_hex(&path)?;

    Ok(AllowedSignersInfo {
        ok: true,
        path: path.display().to_string(),
        text,
        sha256,
    })
}

#[tauri::command]
pub fn get_latest_workbench_runs() -> Result<Vec<LatestRunInfo>, String> {
    let repo = repo_root()?;
    let runs_root = workbench_runs_dir(&repo);
    if !runs_root.exists() {
        return Ok(vec![]);
    }

    let mut dirs: Vec<_> = fs::read_dir(&runs_root)
        .map_err(|e| format!("RUNS_READ_FAILED: {}", e))?
        .filter_map(|x| x.ok())
        .filter(|x| x.path().is_dir())
        .collect();

    dirs.sort_by_key(|x| x.file_name());
    dirs.reverse();

    let mut out: Vec<LatestRunInfo> = Vec::new();

    for entry in dirs.into_iter().take(20) {
        let run_dir = entry.path();
        let run_id = entry.file_name().to_string_lossy().to_string();
        let stdout_path = run_dir.join("stdout.txt");
        let stderr_path = run_dir.join("stderr.txt");
        let sha256sums_path = run_dir.join("sha256sums.txt");

        let stdout = fs::read_to_string(&stdout_path).unwrap_or_default();

        let kind = if stdout.contains("NEVERLOST_TIER0_FULL_GREEN") {
            "verification".to_string()
        } else if stdout.contains("NEVERLOST_VECTORS_FULL_GREEN") {
            "validation".to_string()
        } else {
            "unknown".to_string()
        };

        out.push(LatestRunInfo {
            kind,
            run_id,
            run_dir: run_dir.display().to_string(),
            stdout_path: stdout_path.display().to_string(),
            stderr_path: stderr_path.display().to_string(),
            sha256sums_path: sha256sums_path.display().to_string(),
        });
    }

    Ok(out)
}

#[tauri::command]
pub fn open_path(path: String) -> Result<(), String> {
    let p = std::path::PathBuf::from(&path);
    let safe_path = ensure_allowed_evidence_path(&p)
        .map_err(|e| e.replace("FILE_MISSING", "OPEN_PATH_MISSING"))?;

    if cfg!(windows) {
        if safe_path.is_dir() {
            std::process::Command::new("explorer")
                .arg(safe_path)
                .spawn()
                .map_err(|e| format!("OPEN_DIR_FAILED: {}", e))?;
            return Ok(());
        }

        let select_arg = format!("/select,{}", safe_path.display());

        std::process::Command::new("explorer")
            .arg(select_arg)
            .spawn()
            .map_err(|e| format!("OPEN_FILE_IN_EXPLORER_FAILED: {}", e))?;

        return Ok(());
    }

    // Other desktops: reveal the containing folder (never execute the evidence file itself).
    let folder = if safe_path.is_dir() {
        safe_path.clone()
    } else {
        safe_path
            .parent()
            .map(|p| p.to_path_buf())
            .ok_or_else(|| "OPEN_PATH_NO_PARENT".to_string())?
    };
    let opener = if cfg!(target_os = "macos") { "open" } else { "xdg-open" };
    std::process::Command::new(opener)
        .arg(folder)
        .spawn()
        .map_err(|e| format!("OPEN_DIR_FAILED: {}", e))?;

    Ok(())
}

#[tauri::command]
pub fn get_authority_status() -> Result<AuthorityStatus, String> {
    let root = repo_root()?;
    let session_path = active_authority_session_path(&root);
    if !session_path.exists() {
        return Ok(AuthorityStatus {
            ok: true,
            active: false,
            principal: String::new(),
            session_id: String::new(),
            started_utc: String::new(),
            ended_utc: String::new(),
        });
    }

    let text = fs::read_to_string(&session_path)
        .map_err(|e| format!("AUTHORITY_STATUS_READ_FAILED: {}", e))?;
    let value: serde_json::Value =
        serde_json::from_str(&text).map_err(|e| format!("AUTHORITY_STATUS_PARSE_FAILED: {}", e))?;

    Ok(AuthorityStatus {
        ok: true,
        active: value
            .get("active")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
        principal: value
            .get("principal")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        session_id: value
            .get("session_id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        started_utc: value
            .get("started_utc")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        ended_utc: value
            .get("ended_utc")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
    })
}

#[derive(serde::Serialize)]
pub struct CliActionResult {
    ok: bool,
    area: String,
    action: String,
    exit_code: i32,
    stdout: String,
    stderr: String,
    source: String,
    source_detail: String,
    actor_id: String,
    actor_role: String,
    actor_display_name: String,
}

fn append_authority_action_receipt(
    repo_root: &Path,
    mode_dir: &str,
    area: &str,
    action: &str,
    ok: bool,
    decision: &str,
    reason: &str,
    source_dir: &str,
    source_detail: &str,
    actor_id: &str,
    actor_display_name: &str,
    actor_role: &str,
    exit_code: i32,
    stdout: &str,
    stderr: &str,
) -> Result<(), String> {
    let receipt_dir = repo_root
        .join("proofs")
        .join("receipts")
        .join("workbench_modes")
        .join(mode_dir);

    std::fs::create_dir_all(&receipt_dir)
        .map_err(|e| format!("WORKBENCH_RECEIPT_DIR_FAILED: {}", e))?;

    let receipt_path = receipt_dir.join("authority_actions.ndjson");
    let time_utc = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true);

    let receipt = serde_json::json!({
        "schema": "neverlost.workbench.authority_action.v1",
        "time_utc": time_utc,
        "mode": mode_dir,
        "source": source_dir,
        "source_detail": source_detail,
        "actor_id": actor_id,
        "actor_display_name": actor_display_name,
        "actor_role": actor_role,
        "area": area,
        "action": action,
        "ok": ok,
        "decision": decision,
        "reason": reason,
        "exit_code": exit_code,
        "stdout": stdout.trim(),
        "stderr": stderr.trim()
    });

    let line = serde_json::to_string(&receipt)
        .map_err(|e| format!("WORKBENCH_RECEIPT_SERIALIZE_FAILED: {}", e))?;
    use std::io::Write;
    let mut f = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&receipt_path)
        .map_err(|e| format!("WORKBENCH_RECEIPT_OPEN_FAILED: {}", e))?;
    f.write_all(format!("{}\n", line).as_bytes())
        .map_err(|e| format!("WORKBENCH_RECEIPT_WRITE_FAILED: {}", e))?;
    f.sync_all()
        .map_err(|e| format!("WORKBENCH_RECEIPT_SYNC_FAILED: {}", e))?;
    Ok(())
}

#[tauri::command]
pub fn run_neverlost_cli_action(
    area: String,
    action: String,
    mode: Option<String>,
    source: Option<String>,
) -> Result<CliActionResult, String> {
    let repo_root = repo_root()?;
    let cli_path = repo_root.join("scripts").join("neverlost_cli_v1.ps1");

    if !cli_path.exists() {
        return Err(format!("CLI_PATH_MISSING: {}", cli_path.display()));
    }

    let mode_clean = mode.unwrap_or_else(|| "local".to_string()).to_lowercase();
    let mode_dir = if mode_clean == "managed" {
        "managed"
    } else {
        "local"
    };
    let source_clean = source.unwrap_or_else(|| "cli".to_string()).to_lowercase();
    let source_dir = match source_clean.as_str() {
        "tray" => "tray",
        "workbench" => "workbench",
        "admin" => "admin",
        _ => "cli",
    };

    let source_detail = format!("{}.{}.{}", source_dir, area, action);

    let actor_id = local_actor_id();
    let actor_display_name = actor_id.clone();
    let actor_role = match source_dir {
        "admin" => "admin",
        _ => "operator",
    };

    let denied_reason = if area != "authority" {
        Some("UNKNOWN_AREA")
    } else if !matches!(action.as_str(), "start" | "confirm" | "end") {
        Some("UNKNOWN_ACTION")
    } else {
        None
    };

    if let Some(reason) = denied_reason {
        append_authority_action_receipt(
            &repo_root,
            mode_dir,
            &area,
            &action,
            false,
            "deny",
            reason,
            source_dir,
            &source_detail,
            &actor_id,
            &actor_display_name,
            actor_role,
            403,
            "",
            reason,
        )?;

        return Ok(CliActionResult {
            ok: false,
            area,
            action,
            exit_code: 403,
            stdout: "".to_string(),
            stderr: reason.to_string(),
            source: source_dir.to_string(),
            source_detail,
            actor_id,
            actor_role: actor_role.to_string(),
            actor_display_name,
        });
    }

    let output = std::process::Command::new(ps_host())
        .arg("-NoProfile")
        .arg("-NonInteractive")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-File")
        .arg(cli_path)
        .arg("-RepoRoot")
        .arg(repo_root.to_string_lossy().to_string())
        .arg("-Area")
        .arg(area.clone())
        .arg("-Action")
        .arg(action.clone())
        .output()
        .map_err(|e| format!("CLI_EXEC_FAILED: {}", e))?;

    let exit_code = output.status.code().unwrap_or(-1);
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    append_authority_action_receipt(
        &repo_root,
        mode_dir,
        &area,
        &action,
        exit_code == 0,
        if exit_code == 0 { "allow" } else { "error" },
        if exit_code == 0 {
            ""
        } else {
            "CLI_EXIT_NONZERO"
        },
        source_dir,
        &source_detail,
        &actor_id,
        &actor_display_name,
        actor_role,
        exit_code,
        &stdout,
        &stderr,
    )?;

    Ok(CliActionResult {
        ok: exit_code == 0,
        area,
        action,
        exit_code,
        stdout: stdout.trim().to_string(),
        stderr: stderr.trim().to_string(),
        source: source_dir.to_string(),
        source_detail,
        actor_id,
        actor_role: actor_role.to_string(),
        actor_display_name,
    })
}

#[derive(serde::Serialize, serde::Deserialize)]
pub struct WorkbenchModeState {
    mode: String,
}

#[tauri::command]
pub fn get_workbench_mode() -> Result<WorkbenchModeState, String> {
    let repo_root = repo_root()?;
    let path = repo_root
        .join("proofs")
        .join("receipts")
        .join("workbench_mode.json");

    if !path.exists() {
        return Ok(WorkbenchModeState {
            mode: "local".to_string(),
        });
    }

    let raw =
        std::fs::read_to_string(&path).map_err(|e| format!("READ_WORKBENCH_MODE_FAILED: {}", e))?;

    let parsed: serde_json::Value =
        serde_json::from_str(&raw).map_err(|e| format!("PARSE_WORKBENCH_MODE_FAILED: {}", e))?;

    let mode = parsed
        .get("mode")
        .and_then(|v| v.as_str())
        .unwrap_or("local");

    Ok(WorkbenchModeState {
        mode: if mode == "managed" {
            "managed".to_string()
        } else {
            "local".to_string()
        },
    })
}

#[tauri::command]
pub fn set_workbench_mode(mode: String) -> Result<WorkbenchModeState, String> {
    let clean = if mode.to_lowercase() == "managed" {
        "managed"
    } else {
        "local"
    };

    let repo_root = repo_root()?;
    let dir = repo_root.join("proofs").join("receipts");
    std::fs::create_dir_all(&dir)
        .map_err(|e| format!("CREATE_WORKBENCH_MODE_DIR_FAILED: {}", e))?;

    let path = dir.join("workbench_mode.json");
    let body = serde_json::json!({
        "schema": "neverlost.workbench.mode.v1",
        "mode": clean,
        "time_utc": chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
    });

    let text = serde_json::to_string_pretty(&body)
        .map_err(|e| format!("SERIALIZE_WORKBENCH_MODE_FAILED: {}", e))?;

    std::fs::write(&path, text).map_err(|e| format!("WRITE_WORKBENCH_MODE_FAILED: {}", e))?;

    Ok(WorkbenchModeState {
        mode: clean.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    // Tests share the NEVERLOST_ROOT environment variable.
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn fixture_root(name: &str) -> PathBuf {
        let base = std::env::temp_dir().join(format!(
            "neverlost_wb_test_{}_{}",
            name,
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir_all(base.join("scripts")).unwrap();
        fs::create_dir_all(base.join("proofs").join("receipts")).unwrap();
        fs::create_dir_all(base.join("proofs").join("trust")).unwrap();
        fs::write(base.join("scripts").join("neverlost_cli_v1.ps1"), "# stub\n").unwrap();
        base
    }

    #[test]
    fn unknown_action_is_denied_and_receipted_as_valid_ndjson() {
        let _g = ENV_LOCK.lock().unwrap();
        let root = fixture_root("deny");
        std::env::set_var("NEVERLOST_ROOT", &root);

        let res = run_neverlost_cli_action(
            "authority".into(),
            "rm -rf\n\"x\"".into(),
            Some("managed".into()),
            Some("workbench".into()),
        )
        .unwrap();
        assert!(!res.ok);
        assert_eq!(res.exit_code, 403);

        let text = fs::read_to_string(
            root.join("proofs")
                .join("receipts")
                .join("workbench_modes")
                .join("managed")
                .join("authority_actions.ndjson"),
        )
        .unwrap();
        let lines: Vec<&str> = text.lines().collect();
        assert_eq!(lines.len(), 1, "one receipt line, newlines escaped");
        let v: serde_json::Value = serde_json::from_str(lines[0]).unwrap();
        assert_eq!(v["decision"], "deny");
        assert_eq!(v["reason"], "UNKNOWN_ACTION");
        assert_eq!(v["schema"], "neverlost.workbench.authority_action.v1");

        let res2 = run_neverlost_cli_action("trust".into(), "start".into(), None, None).unwrap();
        assert_eq!(res2.stderr, "UNKNOWN_AREA");

        std::env::remove_var("NEVERLOST_ROOT");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn evidence_reads_are_confined_to_trust_and_receipt_roots() {
        let _g = ENV_LOCK.lock().unwrap();
        let root = fixture_root("confine");
        std::env::set_var("NEVERLOST_ROOT", &root);

        let inside = root.join("proofs").join("receipts").join("neverlost.ndjson");
        fs::write(&inside, "{}\n").unwrap();
        assert!(read_file_text(inside.display().to_string()).is_ok());

        let outside = root.join("scripts").join("neverlost_cli_v1.ps1");
        let err = read_file_text(outside.display().to_string()).err().unwrap();
        assert!(err.starts_with("PATH_OUTSIDE_EVIDENCE_ROOTS"), "{}", err);

        let traversal = root
            .join("proofs")
            .join("receipts")
            .join("..")
            .join("..")
            .join("scripts")
            .join("neverlost_cli_v1.ps1");
        let err2 = read_file_text(traversal.display().to_string()).err().unwrap();
        assert!(err2.starts_with("PATH_OUTSIDE_EVIDENCE_ROOTS"), "{}", err2);

        std::env::remove_var("NEVERLOST_ROOT");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn ps_host_honors_override() {
        let _g = ENV_LOCK.lock().unwrap();
        std::env::set_var("NEVERLOST_PS_HOST", "/opt/custom/pwsh");
        assert_eq!(ps_host(), "/opt/custom/pwsh");
        std::env::remove_var("NEVERLOST_PS_HOST");
        if cfg!(windows) {
            assert!(ps_host().ends_with(r"WindowsPowerShell\v1.0\powershell.exe"));
        } else {
            assert_eq!(ps_host(), "pwsh");
        }
    }
}
