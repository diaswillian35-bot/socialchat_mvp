import Foundation

/// Espelho da sessão no App Group (arquivo + UserDefaults).
enum ShareAppGroupSession {
  static let suiteName = "group.com.remdy.app"
  private static let tokenKey = "share_extension_session_v1.token"
  private static let sidKey = "share_extension_session_v1.sid"
  private static let expKey = "share_extension_session_v1.expiresAtMs"
  private static let sessionFile = "share_session/session_v1.json"
  private static let statusFile = "share_session/status_v1.json"

  struct SaveReport {
    var containerOk = false
    var fileOk = false
    var defaultsOk = false

    var sharedOk: Bool { fileOk }
  }

  static func containerURL() -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
  }

  @discardableResult
  static func save(_ session: ShareSessionKeychain.Session) -> Bool {
    saveDetailed(session).sharedOk
  }

  static func saveDetailed(_ session: ShareSessionKeychain.Session) -> SaveReport {
    var report = SaveReport()
    if let root = containerURL() {
      report.containerOk = true
      report.fileOk = writeSessionFile(session, root: root)
    } else {
      NSLog("RemdyShareSession app group container unavailable")
    }
    report.defaultsOk = saveDefaults(session)
    return report
  }

  static func load() -> ShareSessionKeychain.Session? {
    loadFile() ?? loadDefaults()
  }

  static func loadFile() -> ShareSessionKeychain.Session? {
    guard let url = sessionFileURL(),
          let data = try? Data(contentsOf: url)
    else { return nil }
    return ShareSessionKeychain.session(fromPayload: data)
  }

  static func loadDefaults() -> ShareSessionKeychain.Session? {
    guard let suite = UserDefaults(suiteName: suiteName) else { return nil }
    let obj: [String: Any] = [
      "token": suite.string(forKey: tokenKey) ?? "",
      "sid": suite.string(forKey: sidKey) ?? "",
      "expiresAtMs": suite.object(forKey: expKey) as Any,
    ]
    return ShareSessionKeychain.session(from: obj)
  }

  @discardableResult
  static func clear() -> Bool {
    if let url = sessionFileURL() {
      try? FileManager.default.removeItem(at: url)
    }
    if let url = statusFileURL() {
      try? FileManager.default.removeItem(at: url)
    }
    guard let suite = UserDefaults(suiteName: suiteName) else { return false }
    suite.removeObject(forKey: tokenKey)
    suite.removeObject(forKey: sidKey)
    suite.removeObject(forKey: expKey)
    suite.synchronize()
    return true
  }

  static func writeStatus(_ values: [String: Any]) {
    guard let url = statusFileURL() else { return }
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard JSONSerialization.isValidJSONObject(values),
          let data = try? JSONSerialization.data(withJSONObject: values)
    else { return }
    try? data.write(to: url, options: .atomic)
  }

  private static func saveDefaults(_ session: ShareSessionKeychain.Session) -> Bool {
    guard let suite = UserDefaults(suiteName: suiteName) else { return false }
    suite.set(session.token, forKey: tokenKey)
    suite.set(session.sid, forKey: sidKey)
    suite.set(NSNumber(value: session.expiresAtMs), forKey: expKey)
    suite.synchronize()
    return loadDefaults() != nil
  }

  private static func writeSessionFile(
    _ session: ShareSessionKeychain.Session,
    root: URL
  ) -> Bool {
    guard let data = ShareSessionKeychain.sessionPayloadData(session) else { return false }
    let url = root.appendingPathComponent(sessionFile)
    let dir = url.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      return loadFile() != nil
    } catch {
      NSLog("RemdyShareSession file save failed")
      return false
    }
  }

  private static func sessionFileURL() -> URL? {
    containerURL()?.appendingPathComponent(sessionFile)
  }

  private static func statusFileURL() -> URL? {
    containerURL()?.appendingPathComponent(statusFile)
  }

  static func saveDestinations(_ payload: [String: Any]) -> Bool {
    guard let root = containerURL() else { return false }
    var obj = payload
    obj["savedAtMs"] = NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000))
    guard JSONSerialization.isValidJSONObject(obj),
          let data = try? JSONSerialization.data(withJSONObject: obj)
    else { return false }
    let url = root.appendingPathComponent("share_session/destinations_v1.json")
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: url, options: .atomic)
      let dms = (obj["conversations"] as? [Any])?.count ?? 0
      let groups = (obj["groups"] as? [Any])?.count ?? 0
      NSLog("RemdyShareSession destinations saved dms=%d groups=%d", dms, groups)
      return true
    } catch {
      NSLog("RemdyShareSession destinations save failed")
      return false
    }
  }

  static func loadDestinations() -> [String: Any]? {
    guard let root = containerURL() else { return nil }
    let url = root.appendingPathComponent("share_session/destinations_v1.json")
    guard let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return obj
  }
}
