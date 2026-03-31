use chrono::Utc;
use serde::Serialize;
use sha2::Digest;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const NEVERLOST_ROOT: &str = r"C:\dev\neverlost";
const PS_EXE: &str = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe";

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

#[derive(Serialize)]
pub struct AuthorityActionResult {
    ok: bool,
    action: String,
    session_id: String,
}

fn scripts_dir() -> PathBuf {
    Path::new(NEVERLOST_ROOT).join("scripts")
}

fn receipts_dir() -> PathBuf {
    Path::new(NEVERLOST_ROOT).join("proofs").join("receipts")
}

fn trust_dir() -> PathBuf {
    Path::new(NEVERLOST_ROOT).join("proofs").join("trust")
}

fn workbench_runs_dir() -> PathBuf {
    receipts_dir().join("workbench_runs")
}

fn active_authority_session_path() -> PathBuf {
    receipts_dir().join("active_authority_session.json")
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

    write_file(&sha_path, &lines.join("\n"))?;
    Ok(sha_path)
}

fn run_ps_script(script_name: &str, success_token: &str) -> Result<EvidenceBundle, String> {
    let run_id = utc_now();
    let run_dir = workbench_runs_dir().join(&run_id);
    fs::create_dir_all(&run_dir).map_err(|e| format!("RUN_DIR_CREATE_FAILED: {}", e))?;

    let runner_path = scripts_dir().join(script_name);
    if !runner_path.exists() {
        return Err(format!("RUNNER_MISSING: {}", runner_path.display()));
    }

    let output = Command::new(PS_EXE)
        .arg("-NoProfile")
        .arg("-NonInteractive")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-File")
        .arg(&runner_path)
        .arg("-RepoRoot")
        .arg(NEVERLOST_ROOT)
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

fn run_authority_script(script_name: &str, action: &str) -> Result<AuthorityActionResult, String> {
    let runner_path = scripts_dir().join(script_name);
    if !runner_path.exists() {
        return Err(format!("RUNNER_MISSING: {}", runner_path.display()));
    }

    let output = Command::new(PS_EXE)
        .arg("-NoProfile")
        .arg("-NonInteractive")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-File")
        .arg(&runner_path)
        .arg("-RepoRoot")
        .arg(NEVERLOST_ROOT)
        .output()
        .map_err(|e| format!("PROCESS_START_FAILED: {}", e))?;

    if !output.status.success() {
        return Err(format!(
            "AUTHORITY_SCRIPT_FAILED: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout).replace("\r\n", "\n");
    let session_id = stdout
        .lines()
        .find_map(|line| line.strip_prefix("SESSION_ID="))
        .unwrap_or("")
        .trim()
        .to_string();

    Ok(AuthorityActionResult {
        ok: true,
        action: action.to_string(),
        session_id,
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
    let ledger_path = receipts_dir().join("neverlost.ndjson");
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
    if !pb.exists() {
        return Err(format!("FILE_MISSING: {}", path));
    }

    let text = fs::read_to_string(&pb)
        .map_err(|e| format!("FILE_READ_FAILED: {}", e))?
        .replace("\r\n", "\n");

    Ok(FileTextResult {
        ok: true,
        path,
        text,
    })
}

#[tauri::command]
pub fn get_trust_bundle_info() -> Result<TrustBundleInfo, String> {
    let path = trust_dir().join("trust_bundle.json");
    let expected_principal_path = trust_dir().join("expected_principal0.txt");
    let expected_namespaces_path = trust_dir().join("expected_namespaces_principal0.txt");

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
    let path = trust_dir().join("allowed_signers");
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
    let root = workbench_runs_dir();
    if !root.exists() {
        return Ok(vec![]);
    }

    let mut dirs: Vec<_> = fs::read_dir(&root)
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
    let pb = PathBuf::from(&path);
    if !pb.exists() {
        return Err(format!("OPEN_PATH_MISSING: {}", path));
    }

    Command::new("cmd")
        .args(["/C", "start", "", &path])
        .spawn()
        .map_err(|e| format!("OPEN_PATH_FAILED: {}", e))?;

    Ok(())
}

#[tauri::command]
pub fn get_authority_status() -> Result<AuthorityStatus, String> {
    let session_path = active_authority_session_path();
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
        active: value.get("active").and_then(|v| v.as_bool()).unwrap_or(false),
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

#[tauri::command]
pub fn start_authority() -> Result<AuthorityActionResult, String> {
    run_authority_script("start_authority_v1.ps1", "authority.started")
}

#[tauri::command]
pub fn confirm_authority() -> Result<AuthorityActionResult, String> {
    run_authority_script("confirm_authority_v1.ps1", "authority.confirmed")
}

#[tauri::command]
pub fn end_authority() -> Result<AuthorityActionResult, String> {
    run_authority_script("end_authority_v1.ps1", "authority.ended")
}