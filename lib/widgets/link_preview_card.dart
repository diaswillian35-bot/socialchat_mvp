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
  });

  final String url;
  final String domain;
  final String title;
  final String description;
  final String imageUrl;

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
    );
  }
}

/// Cartão de prévia dentro da mesma bolha (sem nova ValueKey).
class LinkPreviewCard extends StatelessWidget {
  const LinkPreviewCard({
    super.key,
    required this.data,
    required this.isMe,
  });

  final LinkPreviewData data;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final fg = isMe ? Colors.white : const Color(0xFF111827);
    final muted = isMe ? Colors.white70 : const Color(0xFF6B7280);
    final border = isMe ? Colors.white24 : const Color(0xFFE5E7EB);

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
              if (data.imageUrl.isNotEmpty)
                AspectRatio(
                  aspectRatio: 1.9,
                  child: Image.network(
                    data.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data.title.isNotEmpty)
                      Text(
                        data.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      )
                    else
                      Text(
                        t.get('link_preview_unavailable'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
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
                      data.domain,
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
