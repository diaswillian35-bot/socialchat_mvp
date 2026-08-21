import Foundation
import Security

/// Opaque Share Extension session — Keychain Access Group.
enum ShareSessionKeychain {
  static let accessGroup = "CZN2YMTU7B.com.remdy.app.share"
  private static let service = "com.remdy.app.share_extension_session"
  private static let account = "default"

  struct Session: Equatable {
    var token: String
    var sid: String
    var expiresAtMs: Int64
  }

  @discardableResult
  static func save(_ session: Session) -> Bool {
    saveStatus(session) == errSecSuccess
  }

  static func saveStatus(_ session: Session) -> OSStatus {
    clear()
    guard let data = sessionPayloadData(session) else {
      NSLog("RemdyShareSession keychain encode failed sidLen=%d hasToken=%d",
            session.sid.count, session.token.isEmpty ? 0 : 1)
      return errSecParam
    }

    var addQuery = baseQuery(includeAccessGroup: true)
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    addQuery[kSecAttrSynchronizable as String] = kCFBooleanFalse

    var status = SecItemAdd(addQuery as CFDictionary, nil)
    if status == errSecDuplicateItem {
      status = SecItemUpdate(
        baseQuery(includeAccessGroup: true) as CFDictionary,
        [kSecValueData as String: data] as CFDictionary
      )
    }
    NSLog("RemdyShareSession keychain save status=%d sidLen=%d hasToken=%d",
          Int(status), session.sid.count, session.token.isEmpty ? 0 : 1)
    return status
  }

  static func load() -> Session? {
    readSession(includeAccessGroup: true)
  }

  @discardableResult
  static func clear() -> Bool {
    let status = SecItemDelete(baseQuery(includeAccessGroup: true) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  static func sessionPayloadData(_ session: Session) -> Data? {
    let payload: [String: Any] = [
      "token": session.token,
      "sid": session.sid,
      "expiresAtMs": NSNumber(value: session.expiresAtMs),
    ]
    guard JSONSerialization.isValidJSONObject(payload) else { return nil }
    return try? JSONSerialization.data(withJSONObject: payload)
  }

  static func session(fromPayload data: Data) -> Session? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    return session(from: obj)
  }

  static func session(from obj: [String: Any]) -> Session? {
    let token = ((obj["token"] as? String) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let sid = ((obj["sid"] as? String) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty, !sid.isEmpty else { return nil }
    let exp = int64Value(obj["expiresAtMs"])
    if exp > 0, exp < Int64(Date().timeIntervalSince1970 * 1000) {
      return nil
    }
    return Session(token: token, sid: sid, expiresAtMs: exp)
  }

  static func int64Value(_ raw: Any?) -> Int64 {
    if let n = raw as? NSNumber { return n.int64Value }
    if let n = raw as? Int64 { return n }
    if let n = raw as? Int { return Int64(n) }
    if let n = raw as? Double { return Int64(n) }
    if let s = raw as? String, let n = Int64(s) { return n }
    return 0
  }

  private static func baseQuery(includeAccessGroup: Bool) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    if includeAccessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
  }

  private static func readSession(includeAccessGroup: Bool) -> Session? {
    var query = baseQuery(includeAccessGroup: includeAccessGroup)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return session(fromPayload: data)
  }
}
