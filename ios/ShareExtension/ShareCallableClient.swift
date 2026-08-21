import Foundation

/// Firebase callable client for the Share Extension (no Firebase SDK).
enum ShareCallableClient {
  static let projectId = "socialchatmvp"
  static let region = "us-central1"

  struct Destination: Equatable {
    let destinationId: String
    let type: String // dm | group
    let otherUid: String
    let displayName: String
    let photoUrl: String
    let location: String
    let allowed: Bool
    let blockedReason: String
    let online: Bool
    let memberCount: Int
    let lastMessageAtMs: Int64
  }

  enum APIError: Error {
    case http(Int)
    case decode
    case server(String)
    case noSession
    case offline
  }

  static func listDestinations(token: String, query: String) async throws -> (dms: [Destination], groups: [Destination]) {
    let data = try await call(
      name: "listShareDestinations",
      payload: ["token": token, "query": query]
    )
    let dms = parseList(data["conversations"]).sorted { $0.lastMessageAtMs > $1.lastMessageAtMs }
    let groups = parseList(data["groups"])
    return (dms, groups)
  }

  static let maxCachedItems = 30

  static func cachedLists() -> (dms: [Destination], groups: [Destination])? {
    guard let obj = ShareAppGroupSession.loadDestinations() else { return nil }
    let dms = Array(
      parseList(obj["conversations"])
        .sorted { $0.lastMessageAtMs > $1.lastMessageAtMs }
        .prefix(maxCachedItems)
    )
    let groups = Array(parseList(obj["groups"]).prefix(maxCachedItems))
    return (dms, groups)
  }

  static func send(
    token: String,
    destination: Destination,
    text: String,
    intentId: String
  ) async throws -> String {
    var payload: [String: Any] = [
      "token": token,
      "destinationId": destination.destinationId,
      "kind": destination.type,
      "text": text,
      "intentId": intentId,
      "clientNonce": UUID().uuidString,
    ]
    if destination.type == "dm" {
      payload["otherUid"] = destination.otherUid
    }
    let data = try await call(name: "sendShareMessage", payload: payload)
    guard let messageId = data["messageId"] as? String, !messageId.isEmpty else {
      throw APIError.decode
    }
    return messageId
  }

  private static func parseList(_ raw: Any?) -> [Destination] {
    guard let arr = raw as? [[String: Any]] else { return [] }
    return arr.compactMap { row in
      guard let id = row["destinationId"] as? String, !id.isEmpty else { return nil }
      let type = (row["type"] as? String) ?? "dm"
      return Destination(
        destinationId: id,
        type: type,
        otherUid: (row["otherUid"] as? String) ?? "",
        displayName: (row["displayName"] as? String) ?? "Remdy",
        photoUrl: (row["photoUrl"] as? String) ?? "",
        location: (row["location"] as? String) ?? "",
        allowed: (row["allowed"] as? Bool) ?? true,
        blockedReason: (row["blockedReason"] as? String) ?? "",
        online: (row["online"] as? Bool) ?? (row["isOnline"] as? Bool) ?? false,
        memberCount: intValue(row["memberCount"] ?? row["membersCount"] ?? row["participantCount"]),
        lastMessageAtMs: int64Value(row["lastMessageAtMs"] ?? row["updatedAtMs"])
      )
    }
  }

  private static func intValue(_ raw: Any?) -> Int {
    if let n = raw as? Int { return n }
    if let n = raw as? NSNumber { return n.intValue }
    return Int("\(raw ?? "")") ?? 0
  }

  private static func int64Value(_ raw: Any?) -> Int64 {
    if let n = raw as? Int64 { return n }
    if let n = raw as? Int { return Int64(n) }
    if let n = raw as? NSNumber { return n.int64Value }
    return Int64("\(raw ?? "")") ?? 0
  }

  private static func call(name: String, payload: [String: Any]) async throws -> [String: Any] {
    let url = URL(string: "https://\(region)-\(projectId).cloudfunctions.net/\(name)")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 25
    let body: [String: Any] = ["data": payload]
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: req)
    } catch {
      throw APIError.offline
    }
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    if code == 401 || code == 403 {
      throw APIError.noSession
    }
    guard (200..<300).contains(code) else {
      throw APIError.http(code)
    }
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw APIError.decode
    }
    if let error = obj["error"] as? [String: Any] {
      let msg = (error["message"] as? String) ?? "error"
      let status = (error["status"] as? String) ?? ""
      if status == "UNAUTHENTICATED" || msg.lowercased().contains("session") {
        throw APIError.noSession
      }
      throw APIError.server(msg)
    }
    if let result = obj["result"] as? [String: Any] {
      return result
    }
    return obj
  }
}
