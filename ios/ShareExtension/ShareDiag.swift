import Foundation

/// Breadcrumbs only — never tokens, emails, message bodies or photo bytes.
enum ShareDiag {
  private static let fileName = "share_session/diag_v1.log"
  private static let maxBytes = 12_000

  static func log(_ event: String, _ fields: [String: String] = [:]) {
    let ts = Int(Date().timeIntervalSince1970 * 1000)
    var parts = ["t=\(ts)", "e=\(sanitize(event))"]
    for (k, v) in fields.sorted(by: { $0.key < $1.key }) {
      parts.append("\(sanitize(k))=\(sanitize(v))")
    }
    let line = parts.joined(separator: " ") + "\n"
    NSLog("RemdyShareExt %@", line.trimmingCharacters(in: .newlines))
    append(line)
  }

  static func readTail() -> String {
    guard let url = fileURL(),
          let data = try? Data(contentsOf: url),
          let text = String(data: data, encoding: .utf8)
    else { return "" }
    if text.count <= 4000 { return text }
    return String(text.suffix(4000))
  }

  private static func append(_ line: String) {
    guard let url = fileURL() else { return }
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    handle.seekToEndOfFile()
    if let data = line.data(using: .utf8) {
      handle.write(data)
    }
    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
       let size = attrs[.size] as? NSNumber,
       size.intValue > maxBytes {
      let keep = Data((try? Data(contentsOf: url))?.suffix(maxBytes / 2) ?? Data())
      try? keep.write(to: url, options: .atomic)
    }
  }

  private static func fileURL() -> URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: ShareAppGroupSession.suiteName)?
      .appendingPathComponent(fileName)
  }

  private static func sanitize(_ raw: String) -> String {
    var s = raw
    for needle in ["token", "password", "email", "Bearer", "Authorization"] {
      if s.range(of: needle, options: .caseInsensitive) != nil {
        return "redacted"
      }
    }
    s = s.replacingOccurrences(of: "\n", with: " ")
    if s.count > 80 { s = String(s.prefix(80)) }
    return s
  }
}
