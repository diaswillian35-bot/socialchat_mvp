import Foundation

/// Normaliza texto/URL recebidos da aba nativa (Safari, YouTube, Mapas).
enum SharePayloadNormalizer {
  static func normalize(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return "" }

    text = rewriteSchemes(text)
    text = upgradeHttp(text)
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func rewriteSchemes(_ input: String) -> String {
    var text = input
    text = replacePrefix(text, from: "youtube://", to: "https://")
    text = replacePrefix(text, from: "maps://", to: "https://")
    text = rewriteGeo(text)
    return text
  }

  static func upgradeHttp(_ input: String) -> String {
    let ns = input as NSString
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
      return ns.replacingOccurrences(of: "http://", with: "https://", options: .caseInsensitive, range: NSRange(location: 0, length: ns.length))
    }
    let range = NSRange(location: 0, length: ns.length)
    let matches = detector.matches(in: input, options: [], range: range).reversed()
    var result = ns
    for match in matches {
      guard let url = match.url, url.scheme?.lowercased() == "http" else { continue }
      var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
      comps?.scheme = "https"
      guard let https = comps?.url?.absoluteString else { continue }
      result = result.replacingCharacters(in: match.range, with: https) as NSString
    }
    return result as String
  }

  static func isAllowed(_ text: String) -> Bool {
    let lower = text.lowercased()
    if lower.contains("javascript:") || lower.contains("file://") ||
        lower.contains("content://") || lower.contains("data:") ||
        lower.contains("blob:") {
      return false
    }
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
      return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    for match in detector.matches(in: text, options: [], range: range) {
      guard let url = match.url, let scheme = url.scheme?.lowercased() else { continue }
      if scheme == "http" { return false }
      if scheme != "https" { return false }
    }
    return true
  }

  static func firstHttpsHost(_ text: String) -> String? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
      return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    for match in detector.matches(in: text, options: [], range: range) {
      if let url = match.url, url.scheme?.lowercased() == "https" {
        return url.host
      }
    }
    return nil
  }

  private static func replacePrefix(_ input: String, from: String, to: String) -> String {
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: from))"
    guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
      return input
    }
    return re.stringByReplacingMatches(
      in: input,
      options: [],
      range: NSRange(location: 0, length: (input as NSString).length),
      withTemplate: to
    )
  }

  private static func rewriteGeo(_ input: String) -> String {
    guard let re = try? NSRegularExpression(
      pattern: #"\bgeo:(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)"#,
      options: .caseInsensitive
    ) else {
      return input
    }
    return re.stringByReplacingMatches(
      in: input,
      options: [],
      range: NSRange(location: 0, length: (input as NSString).length),
      withTemplate: "https://maps.apple.com/?ll=$1,$2"
    )
  }
}
