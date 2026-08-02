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
  }

  enum APIError: Error {
    case http(Int)
    case decode
    case server(String)
    case noSession
  }

  static func listDestinations(token: String, query: String) async throws -> (dms: [Destination], groups: [Destination]) {
    let data = try await call(
      name: "listShareDestinations",
      payload: ["token": token, "query": query]
    )
    let dms = parseList(data["conversations"])
    let groups = parseList(data["groups"])
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
      return Destination(
        destinationId: id,
        type: (row["type"] as? String) ?? "dm",
        otherUid: (row["otherUid"] as? String) ?? "",
        displayName: (row["displayName"] as? String) ?? "Remdy",
        photoUrl: (row["photoUrl"] as? String) ?? "",
        location: (row["location"] as? String) ?? "",
        allowed: (row["allowed"] as? Bool) ?? true,
        blockedReason: (row["blockedReason"] as? String) ?? ""
      )
    }
  }

  private static func call(name: String, payload: [String: Any]) async throws -> [String: Any] {
    let url = URL(string: "https://\(region)-\(projectId).cloudfunctions.net/\(name)")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 25
    let body: [String: Any] = ["data": payload]
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: req)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(code) else {
      throw APIError.http(code)
    }
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw APIError.decode
    }
    if let error = obj["error"] as? [String: Any] {
      let msg = (error["message"] as? String) ?? "error"
      throw APIError.server(msg)
    }
    if let result = obj["result"] as? [String: Any] {
      return result
    }
    return obj
  }
}
