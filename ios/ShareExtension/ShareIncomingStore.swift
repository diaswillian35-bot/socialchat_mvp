import Foundation
import UIKit

/// App Group inbox: imagens da extensão → host Remdy envia com a sessão Firebase.
enum ShareIncomingStore {
  static let appGroupId = "group.com.remdy.app"
  static let jobsFolder = "share_in_jobs"

  static func containerURL() -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
  }

  static func saveImageJob(
    destinationId: String,
    kind: String,
    otherUid: String,
    intentId: String,
    jpegImages: [Data],
    text: String = ""
  ) -> Bool {
    guard let root = containerURL() else { return false }
    if jpegImages.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return false
    }
    let fm = FileManager.default
    let jobId = intentId.isEmpty ? UUID().uuidString : intentId
    let dir = root.appendingPathComponent(jobsFolder, isDirectory: true)
      .appendingPathComponent(jobId, isDirectory: true)
    do {
      if fm.fileExists(atPath: dir.path) {
        try fm.removeItem(at: dir)
      }
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      var names: [String] = []
      for (i, data) in jpegImages.enumerated() {
        let name = String(format: "img_%02d.jpg", i)
        try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        names.append(name)
      }
      let meta: [String: Any] = [
        "jobId": jobId,
        "intentId": jobId,
        "destinationId": destinationId,
        "kind": kind,
        "otherUid": otherUid,
        "files": names,
        "text": text,
        "createdAtMs": Int(Date().timeIntervalSince1970 * 1000),
      ]
      let json = try JSONSerialization.data(withJSONObject: meta, options: [])
      try json.write(to: dir.appendingPathComponent("job.json"), options: .atomic)
      return true
    } catch {
      return false
    }
  }

  static func peekJobs() -> [[String: Any]] {
    guard let root = containerURL() else { return [] }
    let dir = root.appendingPathComponent(jobsFolder, isDirectory: true)
    let fm = FileManager.default
    guard let jobDirs = try? fm.contentsOfDirectory(
      at: dir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }
    var jobs: [[String: Any]] = []
    for jobDir in jobDirs {
      let jsonURL = jobDir.appendingPathComponent("job.json")
      guard let data = try? Data(contentsOf: jsonURL),
            var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { continue }
      let names = (obj["files"] as? [String]) ?? []
      let paths = names.map { jobDir.appendingPathComponent($0).path }
      obj["filePaths"] = paths
      obj["jobDir"] = jobDir.path
      jobs.append(obj)
    }
    return jobs
  }

  static func removeJob(jobId: String) {
    guard let root = containerURL() else { return }
    let dir = root.appendingPathComponent(jobsFolder, isDirectory: true)
      .appendingPathComponent(jobId, isDirectory: true)
    try? FileManager.default.removeItem(at: dir)
  }

  static func jpegData(from image: UIImage, maxDimension: CGFloat = 1920, quality: CGFloat = 0.8) -> Data? {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return image.jpegData(compressionQuality: quality) }
    let longest = max(size.width, size.height)
    let scale = longest > maxDimension ? maxDimension / longest : 1
    let outSize = CGSize(width: size.width * scale, height: size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: outSize)
    let scaled = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: outSize))
    }
    return scaled.jpegData(compressionQuality: quality)
  }
}
