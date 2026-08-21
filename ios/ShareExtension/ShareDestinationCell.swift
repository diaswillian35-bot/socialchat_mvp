import UIKit

final class ShareDestinationCell: UITableViewCell {
  static let reuseId = "ShareDestinationCell"

  private let avatar = UIImageView()
  private let initialLabel = UILabel()
  private let onlineDot = UIView()
  private let nameLabel = UILabel()
  private let metaLabel = UILabel()
  private let spinner = UIActivityIndicatorView(style: .medium)

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = ShareTheme.canvas
    contentView.backgroundColor = ShareTheme.canvas
    selectionStyle = .default

    avatar.translatesAutoresizingMaskIntoConstraints = false
    avatar.layer.cornerRadius = 20
    avatar.clipsToBounds = true
    avatar.contentMode = .scaleAspectFill
    avatar.backgroundColor = ShareTheme.navy.withAlphaComponent(0.12)

    initialLabel.translatesAutoresizingMaskIntoConstraints = false
    initialLabel.font = .systemFont(ofSize: 15, weight: .bold)
    initialLabel.textColor = ShareTheme.navy
    initialLabel.textAlignment = .center

    onlineDot.translatesAutoresizingMaskIntoConstraints = false
    onlineDot.backgroundColor = ShareTheme.green
    onlineDot.layer.cornerRadius = 5
    onlineDot.layer.borderWidth = 2
    onlineDot.layer.borderColor = UIColor.white.cgColor
    onlineDot.isHidden = true

    nameLabel.translatesAutoresizingMaskIntoConstraints = false
    nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
    nameLabel.textColor = ShareTheme.navy
    nameLabel.numberOfLines = 1

    metaLabel.translatesAutoresizingMaskIntoConstraints = false
    metaLabel.font = .systemFont(ofSize: 12, weight: .medium)
    metaLabel.textColor = ShareTheme.muted
    metaLabel.numberOfLines = 1

    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.hidesWhenStopped = true
    spinner.color = ShareTheme.blue

    contentView.addSubview(avatar)
    contentView.addSubview(initialLabel)
    contentView.addSubview(onlineDot)
    contentView.addSubview(nameLabel)
    contentView.addSubview(metaLabel)
    contentView.addSubview(spinner)

    NSLayoutConstraint.activate([
      avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
      avatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      avatar.widthAnchor.constraint(equalToConstant: 40),
      avatar.heightAnchor.constraint(equalToConstant: 40),

      initialLabel.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
      initialLabel.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),

      onlineDot.widthAnchor.constraint(equalToConstant: 10),
      onlineDot.heightAnchor.constraint(equalToConstant: 10),
      onlineDot.trailingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 1),
      onlineDot.bottomAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 1),

      nameLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
      nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: spinner.leadingAnchor, constant: -8),
      nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),

      metaLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
      metaLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
      metaLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
      metaLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

      spinner.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
      spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) { nil }

  func configure(_ row: ShareCallableClient.Destination, sending: Bool, membersLabel: String) {
    // No remote photo downloads in the extension — avoids jetsam from large CDN images.
    avatar.image = nil
    initialLabel.isHidden = false
    nameLabel.text = row.displayName
    nameLabel.textColor = row.allowed ? ShareTheme.navy : ShareTheme.muted
    let meta: String
    if !row.allowed {
      meta = membersLabel.isEmpty ? "" : membersLabel
    } else if row.memberCount > 0 {
      meta = membersLabel
    } else {
      meta = row.location
    }
    metaLabel.text = meta
    metaLabel.isHidden = meta.isEmpty
    onlineDot.isHidden = !row.online || !row.allowed
    let trimmed = row.displayName.trimmingCharacters(in: .whitespaces)
    initialLabel.text = trimmed.isEmpty ? "R" : String(trimmed.prefix(1)).uppercased()
    if sending {
      spinner.startAnimating()
    } else {
      spinner.stopAnimating()
    }
    alpha = row.allowed ? 1 : 0.55
    isUserInteractionEnabled = row.allowed
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    avatar.image = nil
    initialLabel.isHidden = false
    spinner.stopAnimating()
    onlineDot.isHidden = true
  }
}
