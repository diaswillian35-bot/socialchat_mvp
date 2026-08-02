import 'package:socialchat_mvp/services/message_link_utils.dart';

/// Conteúdo recebido do menu Compartilhar (somente texto / HTTPS).
class ShareInPayload {
  const ShareInPayload({
    required this.intentId,
    required this.text,
    required this.fingerprint,
    required this.receivedAtMs,
    this.subject = '',
    this.source = 'unknown',
    this.primaryLink,
  });

  /// ID opaco do intent nativo (Android/iOS) — nunca é token/senha.
  final String intentId;

  /// Texto sanitizado pronto para edição/envio.
  final String text;

  /// Fingerprint estável para deduplicação.
  final String fingerprint;

  final int receivedAtMs;
  final String subject;
  final String source;

  /// Primeiro link HTTPS detectado (se houver).
  final MessageLinkMatch? primaryLink;

  bool get hasLink => primaryLink != null;

  ShareInPayload copyWithText(String nextText) {
    final trimmed = nextText.trim();
    final links = MessageLinkUtils.extractLinks(trimmed);
    return ShareInPayload(
      intentId: intentId,
      text: trimmed,
      fingerprint: fingerprint,
      receivedAtMs: receivedAtMs,
      subject: subject,
      source: source,
      primaryLink: links.isEmpty ? null : links.first,
    );
  }

  Map<String, dynamic> toJson() => {
        'intentId': intentId,
        'text': text,
        'fingerprint': fingerprint,
        'receivedAtMs': receivedAtMs,
        'subject': subject,
        'source': source,
      };

  factory ShareInPayload.fromJson(Map<String, dynamic> json) {
    final text = (json['text'] ?? '').toString().trim();
    final links = MessageLinkUtils.extractLinks(text);
    return ShareInPayload(
      intentId: (json['intentId'] ?? '').toString(),
      text: text,
      fingerprint: (json['fingerprint'] ?? '').toString(),
      receivedAtMs: (json['receivedAtMs'] is int)
          ? json['receivedAtMs'] as int
          : int.tryParse('${json['receivedAtMs']}') ?? 0,
      subject: (json['subject'] ?? '').toString(),
      source: (json['source'] ?? 'unknown').toString(),
      primaryLink: links.isEmpty ? null : links.first,
    );
  }
}

enum ShareInDestinationKind { conversation, group }

class ShareInDestination {
  const ShareInDestination({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.otherUid = '',
    this.canSend = true,
    this.disabledReasonKey = '',
  });

  final ShareInDestinationKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String otherUid;
  final bool canSend;
  final String disabledReasonKey;
}
