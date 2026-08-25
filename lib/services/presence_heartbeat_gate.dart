/// Gate for best-effort `presence/{uid}/heartbeat` before Rules/CF GO.
///
/// Prefers legacy connection keep-alive. At most **one** new-path write
/// attempt per session; after `permission-denied`, stays off until a new
/// session or [onBackendReady].
class SeparateHeartbeatGate {
  bool probedThisSession = false;
  bool denied = false;
  bool deniedLogged = false;
  int attempts = 0;

  /// Whether a write to the separate heartbeat path should run now.
  bool get shouldAttemptNewPath {
    if (denied) return false;
    if (probedThisSession) return false;
    return true;
  }

  /// Call synchronously **before** the async write to prevent races.
  void markAttemptStarting() {
    probedThisSession = true;
    attempts++;
  }

  void markDenied() {
    denied = true;
  }

  /// One sanitized log for denial (no UID/PII).
  bool consumeDeniedLogSlot() {
    if (deniedLogged) return false;
    deniedLogged = true;
    return true;
  }

  /// New PresenceService session (login / start).
  void onNewSession() {
    probedThisSession = false;
    denied = false;
    deniedLogged = false;
    // attempts is cumulative for debug (before/after); reset optional:
    // keep attempts across session for QA counters, or reset — reset for clarity.
    attempts = 0;
  }

  /// Remote config / flag: backend Rules+CF for separate HB are live.
  void onBackendReady() {
    denied = false;
    probedThisSession = false;
    deniedLogged = false;
  }
}
