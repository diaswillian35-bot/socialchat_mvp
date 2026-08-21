import UIKit
import UniformTypeIdentifiers

/// Share Extension — visual oficial Remdy (sempre claro).
/// Stay open until Cancel or confirmed send success. Never auto-dismiss on error.
@objc(ShareViewController)
final class ShareViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
  /// Hard caps for extension memory budget (~jetsam around tens of MB).
  private let maxImages = 5
  private let maxVisibleDestinations = 30
  private let jpegMaxDimension: CGFloat = 1280
  private let jpegQuality: CGFloat = 0.65

  private var shareText = ""
  private var imageJPEGs: [Data] = []
  private var previewImage: UIImage?
  private var intentId = UUID().uuidString
  private var dms: [ShareCallableClient.Destination] = []
  private var groups: [ShareCallableClient.Destination] = []
  private var sendingId: String?
  private var searchWorkItem: DispatchWorkItem?
  private var segment = 0
  private var didBootstrap = false
  private var didFinish = false
  private var bootstrapTask: Task<Void, Never>?
  private var tableHeightConstraint: NSLayoutConstraint?

  private enum ScreenState {
    case loading
    case ready
    case needLogin
    case offline
    case failed
    case sending
    case sent
  }

  private var state: ScreenState = .loading

  private let logoView = UIImageView()
  private let titleLabel = UILabel()
  private let previewCard = UIView()
  private let previewThumb = UIImageView()
  private let previewLabel = UILabel()
  private let searchBar = UISearchBar()
  private let segmentControl = UISegmentedControl(items: ["", ""])
  private let table = UITableView(frame: .zero, style: .plain)
  private let emptyLabel = UILabel()
  private let statusLabel = UILabel()
  private let retryButton = UIButton(type: .system)
  private let cancelButton = UIButton(type: .system)
  private let spinner = UIActivityIndicatorView(style: .medium)

  private var hasSendableContent: Bool {
    !shareText.isEmpty || !imageJPEGs.isEmpty
  }

  deinit {
    bootstrapTask?.cancel()
    ShareDiag.log("deinit")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    overrideUserInterfaceStyle = .light
    view.backgroundColor = ShareTheme.canvas
    // Non-zero width avoids sheet layout glitches on some iOS versions.
    preferredContentSize = CGSize(width: 320, height: 580)
    isModalInPresentation = true
    buildUI()
    localizeChrome()
    ShareDiag.log("viewDidLoad")
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    ShareDiag.log("viewDidAppear")
    guard !didBootstrap else { return }
    didBootstrap = true
    bootstrapTask = Task { [weak self] in
      await self?.bootstrap()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    ShareDiag.log("viewWillDisappear", [
      "state": "\(state)",
      "finished": didFinish ? "1" : "0",
      "sending": sendingId == nil ? "0" : "1",
    ])
  }

  private func L(_ key: String) -> String {
    let lang = Locale.preferredLanguages.first?.lowercased() ?? "en"
    let table = ShareL10n.table(for: lang)
    if let v = table[key] { return v }
    return ShareL10n.en[key] ?? key
  }

  private func localizeChrome() {
    titleLabel.text = L("share_title")
    segmentControl.setTitle(L("share_tab_chats"), forSegmentAt: 0)
    segmentControl.setTitle(L("share_tab_groups"), forSegmentAt: 1)
    searchBar.placeholder = L("share_search")
    cancelButton.setTitle(L("share_cancel"), for: .normal)
    retryButton.setTitle(L("share_retry"), for: .normal)
  }

  private func buildUI() {
    let root = UIStackView()
    root.axis = .vertical
    root.spacing = 12
    root.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(root)

    NSLayoutConstraint.activate([
      root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      root.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
    ])

    logoView.image = UIImage(named: "remdy_logo") ?? UIImage(named: "remdy_logo.png")
    logoView.contentMode = .scaleAspectFit
    logoView.translatesAutoresizingMaskIntoConstraints = false
    logoView.heightAnchor.constraint(equalToConstant: 36).isActive = true

    titleLabel.font = .systemFont(ofSize: 20, weight: .heavy)
    titleLabel.textColor = ShareTheme.navy
    titleLabel.textAlignment = .center
    titleLabel.accessibilityTraits = .header

    previewCard.backgroundColor = ShareTheme.card
    previewCard.layer.cornerRadius = ShareTheme.corner
    previewCard.layer.borderWidth = 1
    previewCard.layer.borderColor = ShareTheme.border.cgColor
    let previewRow = UIStackView()
    previewRow.axis = .horizontal
    previewRow.spacing = 10
    previewRow.alignment = .center
    previewRow.translatesAutoresizingMaskIntoConstraints = false
    previewCard.addSubview(previewRow)
    NSLayoutConstraint.activate([
      previewRow.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 10),
      previewRow.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 10),
      previewRow.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -10),
      previewRow.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -10),
    ])
    previewThumb.translatesAutoresizingMaskIntoConstraints = false
    previewThumb.layer.cornerRadius = 8
    previewThumb.clipsToBounds = true
    previewThumb.contentMode = .scaleAspectFill
    previewThumb.backgroundColor = ShareTheme.navy.withAlphaComponent(0.08)
    previewThumb.widthAnchor.constraint(equalToConstant: 44).isActive = true
    previewThumb.heightAnchor.constraint(equalToConstant: 44).isActive = true
    previewThumb.isHidden = true
    previewLabel.font = .systemFont(ofSize: 14, weight: .medium)
    previewLabel.textColor = ShareTheme.navy
    previewLabel.numberOfLines = 2
    previewRow.addArrangedSubview(previewThumb)
    previewRow.addArrangedSubview(previewLabel)

    searchBar.searchBarStyle = .minimal
    searchBar.delegate = self
    searchBar.barTintColor = ShareTheme.canvas
    searchBar.backgroundColor = ShareTheme.canvas
    searchBar.searchTextField.backgroundColor = ShareTheme.card
    searchBar.searchTextField.textColor = ShareTheme.navy
    searchBar.searchTextField.layer.cornerRadius = 10
    searchBar.searchTextField.clipsToBounds = true
    searchBar.accessibilityLabel = L("share_search")

    segmentControl.selectedSegmentIndex = 0
    segmentControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    segmentControl.selectedSegmentTintColor = ShareTheme.navy
    segmentControl.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 13, weight: .bold)], for: .selected)
    segmentControl.setTitleTextAttributes([.foregroundColor: ShareTheme.navy, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .normal)
    segmentControl.backgroundColor = ShareTheme.card

    table.dataSource = self
    table.delegate = self
    table.register(ShareDestinationCell.self, forCellReuseIdentifier: ShareDestinationCell.reuseId)
    table.backgroundColor = ShareTheme.canvas
    table.separatorColor = ShareTheme.border
    table.layer.cornerRadius = ShareTheme.corner
    table.layer.borderWidth = 1
    table.layer.borderColor = ShareTheme.border.cgColor
    table.rowHeight = 64
    table.estimatedRowHeight = 64
    table.isScrollEnabled = true
    table.alwaysBounceVertical = true
    table.translatesAutoresizingMaskIntoConstraints = false
    // Critical: fixed height so UITableView scrolls instead of expanding (jetsam).
    let tableHeight = table.heightAnchor.constraint(equalToConstant: 280)
    tableHeight.isActive = true
    tableHeightConstraint = tableHeight

    emptyLabel.font = .systemFont(ofSize: 14, weight: .medium)
    emptyLabel.textColor = ShareTheme.muted
    emptyLabel.textAlignment = .center
    emptyLabel.numberOfLines = 0
    emptyLabel.isHidden = true

    statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    statusLabel.textColor = ShareTheme.navy
    statusLabel.numberOfLines = 0
    statusLabel.textAlignment = .center

    retryButton.backgroundColor = ShareTheme.blue
    retryButton.setTitleColor(.white, for: .normal)
    retryButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
    retryButton.layer.cornerRadius = ShareTheme.corner
    retryButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
    retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
    retryButton.isHidden = true

    cancelButton.setTitleColor(ShareTheme.navy, for: .normal)
    cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
    cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

    spinner.color = ShareTheme.blue
    spinner.hidesWhenStopped = true

    [logoView, titleLabel, previewCard, searchBar, segmentControl, table, emptyLabel, spinner, statusLabel, retryButton, cancelButton]
      .forEach { root.addArrangedSubview($0) }
  }

  private func extractSharePayload() async -> (text: String, images: [Data], thumb: UIImage?) {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      return ("", [], nil)
    }
    var text = ""
    var urlString: String?
    var images: [Data] = []
    var thumb: UIImage?

    for item in items {
      if Task.isCancelled { break }
      guard let attachments = item.attachments else { continue }
      for provider in attachments {
        if Task.isCancelled { break }
        if images.count >= maxImages { break }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
            if url.isFileURL {
              if let jpeg = jpegFromFileURL(url), images.count < maxImages {
                images.append(jpeg)
                if thumb == nil { thumb = smallThumb(from: jpeg) }
              }
            } else {
              urlString = url.absoluteString
            }
          }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
          if let t = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
            // Cap text length to keep extension memory/UI stable.
            let clipped = t.count > 4000 ? String(t.prefix(4000)) : t
            text += (text.isEmpty ? "" : "\n") + clipped
          }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
          if let jpeg = await jpegFromProvider(provider), images.count < maxImages {
            images.append(jpeg)
            if thumb == nil { thumb = smallThumb(from: jpeg) }
          }
        }
      }
    }

    if let u = urlString, !text.contains(u) {
      text = text.isEmpty ? u : text + "\n" + u
    }
    text = SharePayloadNormalizer.normalize(text)
    return (text, images, thumb)
  }

  private func smallThumb(from jpeg: Data) -> UIImage? {
    guard let image = UIImage(data: jpeg) else { return nil }
    let maxSide: CGFloat = 88
    let longest = max(image.size.width, image.size.height)
    guard longest > maxSide else { return image }
    let scale = maxSide / longest
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
  }

  private func jpegFromProvider(_ provider: NSItemProvider) async -> Data? {
    if let image = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) as? UIImage {
      return ShareIncomingStore.jpegData(from: image, maxDimension: jpegMaxDimension, quality: jpegQuality)
    }
    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) as? URL {
      return jpegFromFileURL(url)
    }
    if let data = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) as? Data,
       let image = UIImage(data: data) {
      return ShareIncomingStore.jpegData(from: image, maxDimension: jpegMaxDimension, quality: jpegQuality)
    }
    return nil
  }

  private func jpegFromFileURL(_ url: URL) -> Data? {
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed { url.stopAccessingSecurityScopedResource() }
    }
    guard let image = UIImage(contentsOfFile: url.path) ?? (try? Data(contentsOf: url)).flatMap(UIImage.init(data:)) else {
      return nil
    }
    return ShareIncomingStore.jpegData(from: image, maxDimension: jpegMaxDimension, quality: jpegQuality)
  }

  private func bootstrap() async {
    ShareDiag.log("bootstrap_start")
    applyState(.loading, status: L("share_loading"))
    let extracted = await extractSharePayload()
    if Task.isCancelled { return }
    shareText = extracted.text
    imageJPEGs = extracted.images
    previewImage = extracted.thumb
    let approxKB = imageJPEGs.reduce(0) { $0 + $1.count } / 1024
    ShareDiag.log("payload", [
      "textLen": "\(shareText.count)",
      "images": "\(imageJPEGs.count)",
      "jpegKB": "\(approxKB)",
    ])
    await MainActor.run {
      previewLabel.text = previewText()
      if let thumb = previewImage {
        previewThumb.image = thumb
        previewThumb.isHidden = false
      }
    }

    if !hasSendableContent || (!shareText.isEmpty && !SharePayloadNormalizer.isAllowed(shareText)) {
      ShareDiag.log("payload_rejected")
      applyState(.failed, status: L("share_failed"))
      return
    }

    await loadDestinations()
  }

  private func loadDestinations() async {
    applyState(.loading, status: L("share_loading"))
    if let session = ShareSessionStore.load() {
      ShareDiag.log("session_present", ["sidLen": "\(session.sid.count)"])
      do {
        let lists = try await ShareCallableClient.listDestinations(
          token: session.token,
          query: searchBar.text ?? ""
        )
        if Task.isCancelled { return }
        await MainActor.run {
          self.applyLists(dms: lists.dms, groups: lists.groups, source: "callable")
        }
        return
      } catch ShareCallableClient.APIError.offline {
        if applyCachedDestinations() { return }
        ShareDiag.log("offline_no_cache")
        applyState(.offline, status: L("share_offline"))
        return
      } catch ShareCallableClient.APIError.noSession {
        if applyCachedDestinations() { return }
        ShareDiag.log("session_invalid")
        applyState(.needLogin, status: L("share_need_login"))
        return
      } catch {
        if applyCachedDestinations() { return }
        ShareDiag.log("list_failed", ["type": "\(type(of: error))"])
        applyState(.failed, status: L("share_failed"))
        return
      }
    }
    if applyCachedDestinations() { return }
    ShareDiag.log("no_session_no_cache")
    applyState(.needLogin, status: L("share_need_login"))
  }

  private func applyLists(
    dms rawDms: [ShareCallableClient.Destination],
    groups rawGroups: [ShareCallableClient.Destination],
    source: String
  ) {
    dms = Array(rawDms.prefix(maxVisibleDestinations))
    groups = Array(rawGroups.prefix(maxVisibleDestinations))
    ShareDiag.log("lists_ready", [
      "source": source,
      "dms": "\(dms.count)",
      "groups": "\(groups.count)",
      "cappedDms": rawDms.count > maxVisibleDestinations ? "1" : "0",
      "cappedGroups": rawGroups.count > maxVisibleDestinations ? "1" : "0",
    ])
    applyState(.ready, status: "")
    reloadTable()
  }

  @discardableResult
  private func applyCachedDestinations() -> Bool {
    guard let lists = ShareCallableClient.cachedLists() else { return false }
    applyLists(dms: lists.dms, groups: lists.groups, source: "cache")
    return true
  }

  private func previewText() -> String {
    if !shareText.isEmpty {
      return shareText.count > 120 ? String(shareText.prefix(117)) + "…" : shareText
    }
    if imageJPEGs.count == 1 { return L("share_one_photo") }
    if imageJPEGs.count > 1 {
      return L("share_n_photos").replacingOccurrences(of: "{n}", with: "\(imageJPEGs.count)")
    }
    return "—"
  }

  private func currentRows() -> [ShareCallableClient.Destination] {
    let q = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let base = segment == 0 ? dms : groups
    if q.isEmpty { return base }
    return base.filter { $0.displayName.lowercased().contains(q) }
  }

  private func reloadTable() {
    table.reloadData()
    let rows = currentRows()
    let emptyKey = segment == 0 ? "share_empty_chats" : "share_empty_groups"
    emptyLabel.text = L(emptyKey)
    emptyLabel.isHidden = !(state == .ready && rows.isEmpty)
  }

  private func applyState(_ next: ScreenState, status: String) {
    let work = {
      self.state = next
      self.statusLabel.text = status
      self.statusLabel.textColor = next == .sent ? ShareTheme.green : ShareTheme.navy
      let browsing = next == .ready || next == .sending
      self.searchBar.isHidden = !browsing
      self.segmentControl.isHidden = !browsing
      self.table.isHidden = !browsing
      self.retryButton.isHidden = !(next == .failed || next == .offline)
      if next == .needLogin {
        self.searchBar.isHidden = true
        self.segmentControl.isHidden = true
        self.table.isHidden = true
        self.emptyLabel.isHidden = true
      }
      if next == .loading || next == .sending {
        self.spinner.startAnimating()
      } else {
        self.spinner.stopAnimating()
      }
      if next != .ready { self.emptyLabel.isHidden = true }
      self.table.isUserInteractionEnabled = next == .ready
      self.searchBar.isUserInteractionEnabled = next == .ready
      self.cancelButton.isEnabled = next != .sending
    }
    if Thread.isMainThread {
      work()
    } else {
      DispatchQueue.main.async(execute: work)
    }
  }

  @objc private func segmentChanged() {
    segment = segmentControl.selectedSegmentIndex
    reloadTable()
  }

  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    reloadTable()
    searchWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      Task { await self?.runSearch(searchText) }
    }
    searchWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
  }

  private func runSearch(_ q: String) async {
    // Local filter first (already applied in currentRows). Remote only if session exists.
    if let session = ShareSessionStore.load(), !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      do {
        let lists = try await ShareCallableClient.listDestinations(token: session.token, query: q)
        if Task.isCancelled { return }
        await MainActor.run {
          self.applyLists(dms: lists.dms, groups: lists.groups, source: "search")
        }
        return
      } catch {
        // Keep cached/local list.
      }
    }
    await MainActor.run { self.reloadTable() }
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    currentRows().count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: ShareDestinationCell.reuseId, for: indexPath) as! ShareDestinationCell
    let rows = currentRows()
    guard indexPath.row < rows.count else { return cell }
    let row = rows[indexPath.row]
    var members = ""
    if row.type == "group", row.memberCount > 0 {
      members = L("share_members").replacingOccurrences(of: "{n}", with: "\(row.memberCount)")
    } else if !row.allowed {
      members = L("share_no_permission")
    }
    cell.configure(row, sending: sendingId == row.destinationId, membersLabel: members)
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let rows = currentRows()
    guard indexPath.row < rows.count else { return }
    let row = rows[indexPath.row]
    guard row.allowed, sendingId == nil, state == .ready, !didFinish else { return }
    send(to: row)
  }

  private func send(to dest: ShareCallableClient.Destination) {
    sendingId = dest.destinationId
    applyState(.sending, status: L("share_sending"))
    table.reloadData()
    let text = shareText
    let images = imageJPEGs
    let intent = intentId
    ShareDiag.log("send_start", [
      "kind": dest.type,
      "images": "\(images.count)",
      "textLen": "\(text.count)",
    ])
    Task { [weak self] in
      guard let self else { return }
      do {
        var textQueued = text.isEmpty
        if !text.isEmpty {
          if let session = ShareSessionStore.load() {
            do {
              _ = try await ShareCallableClient.send(
                token: session.token,
                destination: dest,
                text: text,
                intentId: intent
              )
              textQueued = true
            } catch {
              textQueued = false
            }
          }
        }
        let needJob = !images.isEmpty || (!text.isEmpty && !textQueued)
        if needJob {
          let saved = ShareIncomingStore.saveImageJob(
            destinationId: dest.destinationId,
            kind: dest.type,
            otherUid: dest.otherUid,
            intentId: intent,
            jpegImages: images,
            text: textQueued ? "" : text
          )
          if !saved { throw ShareCallableClient.APIError.decode }
        }
        if text.isEmpty && images.isEmpty {
          throw ShareCallableClient.APIError.decode
        }
        await MainActor.run {
          ShareDiag.log("send_ok")
          self.applyState(.sent, status: self.L("share_sent"))
          self.finishSuccessfully()
        }
      } catch ShareCallableClient.APIError.noSession {
        await MainActor.run {
          ShareDiag.log("send_need_login")
          self.sendingId = nil
          self.applyState(.needLogin, status: self.L("share_need_login"))
          self.reloadTable()
        }
      } catch ShareCallableClient.APIError.offline {
        await MainActor.run {
          ShareDiag.log("send_offline")
          self.sendingId = nil
          self.applyState(.offline, status: self.L("share_offline"))
          self.reloadTable()
        }
      } catch {
        await MainActor.run {
          ShareDiag.log("send_failed", ["type": "\(type(of: error))"])
          self.sendingId = nil
          self.applyState(.failed, status: self.L("share_failed"))
          self.reloadTable()
        }
      }
    }
  }

  private func finishSuccessfully() {
    guard !didFinish else { return }
    didFinish = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
      guard let self, self.didFinish else { return }
      ShareDiag.log("completeRequest")
      self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
  }

  @objc private func retryTapped() {
    ShareDiag.log("retry")
    Task { await loadDestinations() }
  }

  @objc private func cancelTapped() {
    guard sendingId == nil, !didFinish else { return }
    didFinish = true
    bootstrapTask?.cancel()
    ShareDiag.log("cancelRequest")
    extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0))
  }
}
