// Session reporting module for remote control session tracking.
// Reports session start/heartbeat/end to the management server.

use hbb_common::{config::Config, log, tokio};

/// Base URL for session reporting API (same server as version check)
const SESSION_API_BASE: &str = "http://112.74.59.152:3000";

/// Report session start to the server.
/// Called when a remote peer is authorized to control this device.
pub fn report_session_start(session_id: &str, peer_id: &str) {
    let session_id = session_id.to_string();
    let peer_id = peer_id.to_string();
    let device_id = Config::get_id();
    std::thread::spawn(move || {
        if let Err(e) = do_report_session_start(&session_id, &peer_id, &device_id) {
            log::warn!("Failed to report session start: {:?}", e);
        }
    });
}

/// Report session heartbeat to the server.
/// Should be called every ~30 seconds during an active session.
pub fn report_session_heartbeat(session_id: &str) {
    let session_id = session_id.to_string();
    let device_id = Config::get_id();
    std::thread::spawn(move || {
        if let Err(e) = do_report_session_heartbeat(&session_id, &device_id) {
            log::debug!("Failed to report session heartbeat: {:?}", e);
        }
    });
}

/// Report session end to the server.
/// Called when the remote control session ends.
pub fn report_session_end(session_id: &str) {
    let session_id = session_id.to_string();
    let device_id = Config::get_id();
    std::thread::spawn(move || {
        if let Err(e) = do_report_session_end(&session_id, &device_id) {
            log::warn!("Failed to report session end: {:?}", e);
        }
    });
}

#[tokio::main(flavor = "current_thread")]
async fn do_report_session_start(
    session_id: &str,
    peer_id: &str,
    device_id: &str,
) -> hbb_common::ResultType<()> {
    let url = format!("{}/api/session/start", SESSION_API_BASE);
    let body = serde_json::json!({
        "session_id": session_id,
        "peer_id": peer_id,
    });
    let client = crate::hbbs_http::create_http_client_async(hbb_common::tls::TlsType::NativeTls, true);
    client
        .post(&url)
        .header("X-Device-Id", device_id)
        .header("Content-Type", "application/json")
        .body(body.to_string())
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await?;
    log::info!(
        "[SESSION REPORT] start: session={}, peer={}",
        session_id,
        peer_id
    );
    Ok(())
}

#[tokio::main(flavor = "current_thread")]
async fn do_report_session_heartbeat(
    session_id: &str,
    device_id: &str,
) -> hbb_common::ResultType<()> {
    let url = format!("{}/api/session/heartbeat", SESSION_API_BASE);
    let body = serde_json::json!({
        "session_id": session_id,
    });
    let client = crate::hbbs_http::create_http_client_async(hbb_common::tls::TlsType::NativeTls, true);
    client
        .post(&url)
        .header("X-Device-Id", device_id)
        .header("Content-Type", "application/json")
        .body(body.to_string())
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await?;
    log::debug!("[SESSION REPORT] heartbeat: session={}", session_id);
    Ok(())
}

#[tokio::main(flavor = "current_thread")]
async fn do_report_session_end(
    session_id: &str,
    device_id: &str,
) -> hbb_common::ResultType<()> {
    let url = format!("{}/api/session/end", SESSION_API_BASE);
    let body = serde_json::json!({
        "session_id": session_id,
    });
    let client = crate::hbbs_http::create_http_client_async(hbb_common::tls::TlsType::NativeTls, true);
    client
        .post(&url)
        .header("X-Device-Id", device_id)
        .header("Content-Type", "application/json")
        .body(body.to_string())
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await?;
    log::info!("[SESSION REPORT] end: session={}", session_id);
    Ok(())
}
