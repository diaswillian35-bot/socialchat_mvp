import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/message_link_utils.dart';
import '../services/safe_external_link.dart';

/// Modelo sanitizado de prévia (somente metadados já validados pelo servidor).
class LinkPreviewData {
  const LinkPreviewData({
    required this.url,
    required this.domain,
    this.title = '',
    this.description = '',
    this.imageUrl = '',
    this.provider = '',
    this.fallback = false,
  });

  final String url;
  final String domain;
  final String title;
  final String description;
  final String imageUrl;
  final String provider;
  final bool fallback;

  bool get isInstagram =>
      provider == 'instagram' ||
      domain.toLowerCase().contains('instagram') ||
      domain.toLowerCase().contains('instagr.am');

  static LinkPreviewData? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final url = (map['url'] ?? '').toString().trim();
    if (url.isEmpty) return null;
    final normalized = MessageLinkUtils.normalizeToHttps(url);
    if (normalized == null) return null;
    final domain = (map['domain'] ?? '').toString().trim();
    final imageRaw = (map['imageUrl'] ?? '').toString().trim();
    final imageUrl = MessageLinkUtils.normalizeToHttps(imageRaw) ?? '';
    return LinkPreviewData(
      url: normalized,
      domain: domain.isEmpty
          ? MessageLinkUtils.displayDomain(Uri.parse(normalized).host)
          : domain,
      title: (map['title'] ?? '').toString().trim(),
      description: (map['description'] ?? '').toString().trim(),
      imageUrl: imageUrl,
      provider: (map['provider'] ?? '').toString().trim().toLowerCase(),
      fallback: map['fallback'] == true,
    );
  }
}

/// Shared DM/group decision for what (if anything) sits under the bubble text.
enum LinkPreviewSlotKind { none, loading, card }

class LinkPreviewSlot {
  LinkPreviewSlot._();

  static LinkPreviewSlotKind resolve({
    required bool isDeleted,
    required LinkPreviewData? preview,
    required String status,
    required String messageText,
  }) {
    if (isDeleted) return LinkPreviewSlotKind.none;
    if (preview != null) return LinkPreviewSlotKind.card;
    final normalized = status.trim().toLowerCase();
    if (normalized == 'pending' &&
        MessageLinkUtils.firstPreviewCandidate(messageText) != null) {
      return LinkPreviewSlotKind.loading;
    }
    // `failed` / empty / unknown → keep message + URL only (no card).
    return LinkPreviewSlotKind.none;
  }
}

/// Same wiring for DM (`chat_page`) and group (`group_chat_page`).
class LinkPreviewInBubble extends StatelessWidget {
  const LinkPreviewInBubble({
    super.key,
    required this.isMe,
    required this.isDeleted,
    required this.messageText,
    required this.linkPreviewStatus,
    this.linkPreview,
    this.animateLoading = true,
    this.imageProviderOverride,
  });

  final bool isMe;
  final bool isDeleted;
  final String messageText;
  final String linkPreviewStatus;
  final LinkPreviewData? linkPreview;
  final bool animateLoading;
  final ImageProvider? imageProviderOverride;

  @override
  Widget build(BuildContext context) {
    switch (LinkPreviewSlot.resolve(
      isDeleted: isDeleted,
      preview: linkPreview,
      status: linkPreviewStatus,
      messageText: messageText,
    )) {
      case LinkPreviewSlotKind.card:
        return LinkPreviewCard(
          data: linkPreview!,
          isMe: isMe,
          imageProviderOverride: imageProviderOverride,
        );
      case LinkPreviewSlotKind.loading:
        return LinkPreviewLoadingCard(
          isMe: isMe,
          animate: animateLoading,
        );
      case LinkPreviewSlotKind.none:
        return const SizedBox.shrink();
    }
  }
}

/// Placeholder discreto enquanto `linkPreviewStatus == pending`.
class LinkPreviewLoadingCard extends StatelessWidget {
  const LinkPreviewLoadingCard({
    super.key,
    required this.isMe,
    this.animate = true,
  });

  final bool isMe;

  /// When false, uses a determinate indicator (no ticker) so widget tests
  /// never hang on infinite animation / `pumpAndSettle`.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final muted = isMe ? Colors.white70 : const Color(0xFF6B7280);
    final border = isMe ? Colors.white24 : const Color(0xFFE5E7EB);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: muted,
              value: animate ? null : 0.35,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.get('link_preview_loading'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartão de prévia dentro da mesma bolha (sem nova ValueKey).
class LinkPreviewCard extends StatelessWidget {
  const LinkPreviewCard({
    super.key,
    required this.data,
    required this.isMe,
    this.imageProviderOverride,
  });

  final LinkPreviewData data;
  final bool isMe;

  /// Test seam: avoid real `Image.network` / HTTP.
  final ImageProvider? imageProviderOverride;

  String _title(AppTexts t) {
    if (data.isInstagram && (data.fallback || data.title.isEmpty)) {
      return t.get('link_preview_instagram_post');
    }
    if (data.title.isNotEmpty) return data.title;
    return t.get('link_preview_unavailable');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final fg = isMe ? Colors.white : const Color(0xFF111827);
    final muted = isMe ? Colors.white70 : const Color(0xFF6B7280);
    final border = isMe ? Colors.white24 : const Color(0xFFE5E7EB);
    final showImage = data.imageUrl.isNotEmpty && !data.fallback;
    final showIgIcon = data.isInstagram && !showImage;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          SafeExternalLink.open(
            context,
            url: data.url,
            isRemdyInternal: MessageLinkUtils.isRemdyHost(
              Uri.parse(data.url).host,
            ),
            displayHost: data.domain,
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showImage)
                AspectRatio(
                  aspectRatio: 1.9,
                  child: Image(
                    image: imageProviderOverride ?? NetworkImage(data.imageUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => showIgIcon
                        ? _InstagramFallbackBanner(isMe: isMe)
                        : const SizedBox.shrink(),
                  ),
                )
              else if (showIgIcon)
                _InstagramFallbackBanner(isMe: isMe),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(t),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    if (data.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        data.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      data.domain.isEmpty ? 'instagram.com' : data.domain,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstagramFallbackBanner extends StatelessWidget {
  const _InstagramFallbackBanner({required this.isMe});

  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final bg = isMe ? const Color(0x33FFFFFF) : const Color(0xFFF3F4F6);
    final fg = isMe ? Colors.white : const Color(0xFFE1306C);
    return Container(
      height: 72,
      color: bg,
      alignment: Alignment.center,
      child: Icon(Icons.camera_alt_rounded, color: fg, size: 28),
    );
  }
}
