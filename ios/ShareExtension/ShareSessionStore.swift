import Foundation

/// Sessão compartilhada Runner ↔ ShareExtension (Keychain + App Group file).
enum ShareSessionStore {
  @discardableResult
  static func save(_ session: ShareSessionKeychain.Session) -> Bool {
    let report = saveAndReport(session)
    return (report["ok"] as? Bool) ?? false
  }

  static func saveAndReport(_ session: ShareSessionKeychain.Session) -> [String: Any] {
    let keychainStatus = ShareSessionKeychain.saveStatus(session)
    let keychainOk = keychainStatus == errSecSuccess
    let group = ShareAppGroupSession.saveDetailed(session)
    let shared = hasSharedSession()
    let ok = shared && (keychainOk || group.fileOk)
    let report: [String: Any] = [
      "ok": ok,
      "keychainOk": keychainOk,
      "keychainStatus": Int(keychainStatus),
      "fileOk": group.fileOk,
      "defaultsOk": group.defaultsOk,
      "containerOk": group.containerOk,
      "readable": shared,
      "sidLen": session.sid.count,
      "hasToken": !session.token.isEmpty,
      "expiresAtMs": NSNumber(value: session.expiresAtMs),
    ]
    ShareAppGroupSession.writeStatus(report)
    NSLog(
      "RemdyShareSession save ok=%d keychain=%d file=%d defaults=%d container=%d readable=%d sidLen=%d hasToken=%d",
      ok ? 1 : 0,
      keychainOk ? 1 : 0,
      group.fileOk ? 1 : 0,
      group.defaultsOk ? 1 : 0,
      group.containerOk ? 1 : 0,
      shared ? 1 : 0,
      session.sid.count,
      session.token.isEmpty ? 0 : 1
    )
    return report
  }

  static func hasSharedSession() -> Bool {
    ShareSessionKeychain.load() != nil || ShareAppGroupSession.loadFile() != nil
  }

  /// Copies a host-only UserDefaults session into Keychain + App Group file.
  @discardableResult
  static func promoteIfNeeded() -> Bool {
    if hasSharedSession() {
      NSLog("RemdyShareSession already shared keychain/file")
      return true
    }
    guard let local = ShareAppGroupSession.loadDefaults() else {
      NSLog("RemdyShareSession no session to promote")
      return false
    }
    NSLog("RemdyShareSession promoting defaults-only session sidLen=%d", local.sid.count)
    let report = saveAndReport(local)
    return (report["ok"] as? Bool) ?? false
  }

  static func load() -> ShareSessionKeychain.Session? {
    if let keychain = ShareSessionKeychain.load() {
      ShareAppGroupSession.save(keychain)
      return keychain
    }
    if let file = ShareAppGroupSession.loadFile() {
      return file
    }
    if let local = ShareAppGroupSession.loadDefaults() {
      _ = save(local)
      return ShareSessionKeychain.load() ?? ShareAppGroupSession.loadFile() ?? local
    }
    return nil
  }

  static func meta() -> [String: Any]? {
    promoteIfNeeded()
    guard let session = ShareSessionKeychain.load() ?? ShareAppGroupSession.loadFile() else {
      return nil
    }
    return [
      "sid": session.sid,
      "expiresAtMs": NSNumber(value: session.expiresAtMs),
      "hasToken": !session.token.isEmpty,
      "sidLen": session.sid.count,
    ]
  }

  @discardableResult
  static func clear() -> Bool {
    let a = ShareSessionKeychain.clear()
    let b = ShareAppGroupSession.clear()
    NSLog("RemdyShareSession cleared")
    return a || b
  }
}
