import UIKit
import UniformTypeIdentifiers

/// Share Extension completa — listagem + envio via credencial curta (sem abrir o host).
@objc(ShareViewController)
final class ShareViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
  private let remdyNavy = UIColor(red: 49 / 255, green: 58 / 255, blue: 95 / 255, alpha: 1)
  private let remdyMuted = UIColor(red: 100 / 255, green: 108 / 255, blue: 132 / 255, alpha: 1)

  private var shareText = ""
  private var intentId = UUID().uuidString
  private var dms: [ShareCallableClient.Destination] = []
  private var groups: [ShareCallableClient.Destination] = []
  private var selected: ShareCallableClient.Destination?
  private var sending = false
  private var searchWorkItem: DispatchWorkItem?
  private var segment = 0 // 0 dm, 1 group

  private let scroll = UIScrollView()
  private let content = UIStackView()
  private let titleLabel = UILabel()
  private let previewLabel = UILabel()
  private let domainLabel = UILabel()
  private let searchBar = UISearchBar()
  private let segmentControl = UISegmentedControl(items: ["", ""])
  private let table = UITableView(frame: .zero, style: .plain)
  private let emptyLabel = UILabel()
  private let statusLabel = UILabel()
  private let sendButton = UIButton(type: .system)
  private let cancelButton = UIButton(type: .system)
  private let spinner = UIActivityIndicatorView(style: .medium)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    buildUI()
    localizeChrome()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { await bootstrap() }
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
    sendButton.setTitle(L("share_send"), for: .normal)
    cancelButton.setTitle(L("share_cancel"), for: .normal)
  }

  private func buildUI() {
    scroll.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    content.axis = .vertical
    content.spacing = 12
    content.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(content)
    NSLayoutConstraint.activate([
      content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
      content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
      content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
      content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
      content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
    ])

    titleLabel.font = .preferredFont(forTextStyle: .title2)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = remdyNavy
    titleLabel.accessibilityTraits = .header

    previewLabel.font = .preferredFont(forTextStyle: .body)
    previewLabel.numberOfLines = 6
    previewLabel.adjustsFontForContentSizeCategory = true

    domainLabel.font = .preferredFont(forTextStyle: .caption1)
    domainLabel.textColor = remdyMuted
    domainLabel.numberOfLines = 2

    searchBar.searchBarStyle = .minimal
    searchBar.delegate = self
    searchBar.accessibilityLabel = L("share_search")

    segmentControl.selectedSegmentIndex = 0
    segmentControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    segmentControl.selectedSegmentTintColor = remdyNavy

    table.dataSource = self
    table.delegate = self
    table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    table.translatesAutoresizingMaskIntoConstraints = false
    table.heightAnchor.constraint(equalToConstant: 280).isActive = true
    table.layer.cornerRadius = 8
    table.layer.borderWidth = 1 / UIScreen.main.scale
    table.layer.borderColor = UIColor.separator.cgColor

    emptyLabel.font = .preferredFont(forTextStyle: .footnote)
    emptyLabel.textColor = remdyMuted
    emptyLabel.textAlignment = .center
    emptyLabel.numberOfLines = 0
    emptyLabel.isHidden = true

    statusLabel.font = .preferredFont(forTextStyle: .footnote)
    statusLabel.textColor = remdyMuted
    statusLabel.numberOfLines = 0
    statusLabel.textAlignment = .center

    sendButton.backgroundColor = remdyNavy
    sendButton.setTitleColor(.white, for: .normal)
    sendButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    sendButton.layer.cornerRadius = 10
    sendButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
    sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
    sendButton.isEnabled = false
    sendButton.alpha = 0.5

    cancelButton.setTitleColor(remdyNavy, for: .normal)
    cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

    spinner.hidesWhenStopped = true

    [
      titleLabel, previewLabel, domainLabel, searchBar, segmentControl,
      table, emptyLabel, statusLabel, spinner, sendButton, cancelButton,
    ].forEach { content.addArrangedSubview($0) }
  }

  private func extractSharePayload() async -> String {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      return ""
    }
    var text = ""
    var urlString: String?
    for item in items {
      guard let attachments = item.attachments else { continue }
      for provider in attachments {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
            urlString = url.absoluteString
          }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
          if let t = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
            text += (text.isEmpty ? "" : "\n") + t
          }
        }
      }
    }
    if let u = urlString, !text.contains(u) {
      text = text.isEmpty ? u : text + "\n" + u
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func bootstrap() async {
    setBusy(true, status: L("share_loading"))
    shareText = await extractSharePayload()
    await MainActor.run {
      previewLabel.text = shareText.isEmpty ? "—" : shareText
      domainLabel.text = firstHttpsHost(shareText) ?? ""
    }

    if shareText.isEmpty || !isShareContentAllowed(shareText) {
      await MainActor.run {
        setBusy(false, status: L("share_failed"))
        sendButton.isHidden = true
        searchBar.isUserInteractionEnabled = false
        table.isUserInteractionEnabled = false
      }
      return
    }

    guard let session = ShareSessionKeychain.load() else {
      await MainActor.run {
        setBusy(false, status: L("share_need_login"))
        sendButton.isHidden = true
        searchBar.isUserInteractionEnabled = false
        table.isUserInteractionEnabled = false
      }
      return
    }

    do {
      let lists = try await ShareCallableClient.listDestinations(token: session.token, query: "")
      await MainActor.run {
        self.dms = lists.dms
        self.groups = lists.groups
        self.reloadTable()
        setBusy(false, status: "")
      }
    } catch {
      await MainActor.run {
        setBusy(false, status: L("share_need_login"))
        sendButton.isHidden = true
      }
    }
  }

  private func firstHttpsHost(_ text: String) -> String? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
      return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = detector.matches(in: text, options: [], range: range)
    for m in matches {
      if let url = m.url, url.scheme?.lowercased() == "https" {
        return url.host
      }
    }
    return nil
  }

  /// Client precheck only — server revalidates.
  private func isShareContentAllowed(_ text: String) -> Bool {
    let lower = text.lowercased()
    if lower.contains("javascript:") || lower.contains("file://") || lower.contains("content://") {
      return false
    }
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
      let range = NSRange(text.startIndex..<text.endIndex, in: text)
      for m in detector.matches(in: text, options: [], range: range) {
        guard let url = m.url, let scheme = url.scheme?.lowercased() else { continue }
        if scheme == "http" { return false }
        if scheme != "https" && scheme != "mailto" { return false }
      }
    }
    return true
  }

  private func currentRows() -> [ShareCallableClient.Destination] {
    segment == 0 ? dms : groups
  }

  private func reloadTable() {
    table.reloadData()
    let rows = currentRows()
    emptyLabel.isHidden = !rows.isEmpty
    emptyLabel.text = L("share_empty")
  }

  @objc private func segmentChanged() {
    segment = segmentControl.selectedSegmentIndex
    selected = nil
    updateSendEnabled()
    reloadTable()
  }

  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    searchWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      Task { await self?.runSearch(searchText) }
    }
    searchWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
  }

  private func runSearch(_ q: String) async {
    guard let session = ShareSessionKeychain.load() else { return }
    do {
      let lists = try await ShareCallableClient.listDestinations(token: session.token, query: q)
      await MainActor.run {
        self.dms = lists.dms
        self.groups = lists.groups
        self.reloadTable()
      }
    } catch {
      await MainActor.run {
        self.statusLabel.text = L("share_retry")
      }
    }
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    currentRows().count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
    let row = currentRows()[indexPath.row]
    var config = cell.defaultContentConfiguration()
    config.text = row.displayName
    config.secondaryText = row.allowed
      ? (row.location.isEmpty ? nil : row.location)
      : L("share_no_permission")
    config.textProperties.color = row.allowed ? .label : remdyMuted
    cell.contentConfiguration = config
    cell.selectionStyle = row.allowed ? .default : .none
    cell.accessibilityLabel = row.displayName
    if selected?.destinationId == row.destinationId {
      cell.accessoryType = .checkmark
      cell.tintColor = remdyNavy
    } else {
      cell.accessoryType = .none
    }
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let row = currentRows()[indexPath.row]
    guard row.allowed else { return }
    selected = row
    updateSendEnabled()
    table.reloadData()
  }

  private func updateSendEnabled() {
    let ok = selected != nil && !shareText.isEmpty && !sending
    sendButton.isEnabled = ok
    sendButton.alpha = ok ? 1 : 0.5
  }

  private func setBusy(_ busy: Bool, status: String) {
    if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
    statusLabel.text = status
  }

  @objc private func sendTapped() {
    guard !sending, let dest = selected, let session = ShareSessionKeychain.load() else { return }
    sending = true
    updateSendEnabled()
    setBusy(true, status: L("share_sending"))
    let text = shareText
    let intent = intentId
    Task {
      do {
        _ = try await ShareCallableClient.send(
          token: session.token,
          destination: dest,
          text: text,
          intentId: intent
        )
        await MainActor.run {
          setBusy(false, status: L("share_sent"))
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
          }
        }
      } catch {
        await MainActor.run {
          self.sending = false
          self.updateSendEnabled()
          self.setBusy(false, status: L("share_failed"))
        }
      }
    }
  }

  @objc private func cancelTapped() {
    extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0))
  }
}
