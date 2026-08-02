import Foundation
import Security

/// Opaque Share Extension session — Keychain Access Group only.
enum ShareSessionKeychain {
  static let accessGroup = "CZN2YMTU7B.com.remdy.app.share"
  private static let service = "com.remdy.app.share_extension_session"
  private static let account = "default"

  struct Session: Equatable {
    var token: String
    var sid: String
    var expiresAtMs: Int64
  }

  static func save(_ session: Session) -> Bool {
    clear()
    let payload: [String: Any] = [
      "token": session.token,
      "sid": session.sid,
      "expiresAtMs": session.expiresAtMs,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
      return false
    }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessGroup as String: accessGroup,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    return status == errSecSuccess
  }

  static func load() -> Session? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessGroup as String: accessGroup,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data,
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let token = obj["token"] as? String,
          !token.isEmpty,
          let sid = obj["sid"] as? String
    else { return nil }
    let exp = (obj["expiresAtMs"] as? NSNumber)?.int64Value
      ?? (obj["expiresAtMs"] as? Int64)
      ?? 0
    if exp > 0, exp < Int64(Date().timeIntervalSince1970 * 1000) {
      return nil
    }
    return Session(token: token, sid: sid, expiresAtMs: exp)
  }

  @discardableResult
  static func clear() -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessGroup as String: accessGroup,
    ]
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}
