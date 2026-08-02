import 'dart:convert';

import '../models/share_in_payload.dart';
import 'message_link_utils.dart';

/// Resultado do parse de um compartilhamento externo.
class ShareInParseResult {
  const ShareInParseResult._({
    this.payload,
    this.errorKey,
  });

  factory ShareInParseResult.ok(ShareInPayload payload) =>
      ShareInParseResult._(payload: payload);

  factory ShareInParseResult.error(String errorKey) =>
      ShareInParseResult._(errorKey: errorKey);

  final ShareInPayload? payload;
  final String? errorKey;

  bool get isOk => payload != null;
}

/// Parsing e validação de share-in (texto + HTTPS apenas).
class ShareInParser {
  ShareInParser._();

  static const Set<String> _allowedMimePrefixes = {
    'text/',
  };

  static const Set<String> _allowedExactMimes = {
    'text/plain',
    'text/html', // alguns apps enviam HTML; extraímos texto puro
  };

  static const Set<String> _rejectedMimePrefixes = {
    'image/',
    'video/',
    'audio/',
    'application/',
    'multipart/',
  };

  /// Valida MIME nativo. `null`/vazio = tratado como texto (Android às vezes omite).
  static bool isAllowedMimeType(String? mimeType) {
    final mime = (mimeType ?? '').trim().toLowerCase();
    if (mime.isEmpty || mime == '*/*') {
      // Sem MIME: só aceitamos se o conteúdo for texto (checado no parse).
      return true;
    }
    for (final bad in _rejectedMimePrefixes) {
      if (mime.startsWith(bad)) return false;
    }
    if (_allowedExactMimes.contains(mime)) return true;
    for (final ok in _allowedMimePrefixes) {
      if (mime.startsWith(ok)) return true;
    }
    return false;
  }

  /// Monta payload a partir do mapa nativo do MethodChannel.
  static ShareInParseResult parseNativeMap(Map<dynamic, dynamic> raw) {
    final mime = (raw['mimeType'] ?? raw['type'] ?? '').toString();
    if (!isAllowedMimeType(mime)) {
      return ShareInParseResult.error('share_in_unsupported_type');
    }

    // Rejeita URIs de arquivo/content no campo dedicado.
    final uri = (raw['uri'] ?? raw['stream'] ?? '').toString().trim();
    if (_isForbiddenUri(uri)) {
      return ShareInParseResult.error('share_in_unsupported_type');
    }

    final subject = (raw['subject'] ?? '').toString().trim();
    final textRaw = (raw['text'] ?? raw['content'] ?? '').toString();
    final combined = _combineSubjectAndText(subject: subject, text: textRaw);

    return parseText(
      combined,
      intentId: (raw['intentId'] ?? raw['id'] ?? '').toString(),
      subject: subject,
      source: (raw['source'] ?? 'native').toString(),
      receivedAtMs: _readMs(raw['receivedAtMs']),
      mimeType: mime,
    );
  }

  static ShareInParseResult parseText(
    String input, {
    String intentId = '',
    String subject = '',
    String source = 'test',
    int? receivedAtMs,
    String? mimeType,
  }) {
    if (!isAllowedMimeType(mimeType)) {
      return ShareInParseResult.error('share_in_unsupported_type');
    }

    final cleaned = sanitizeSharedText(input);
    if (cleaned.isEmpty) {
      return ShareInParseResult.error('share_in_invalid');
    }

    // Rejeita se o conteúdo inteiro for um scheme perigoso / content / file.
    if (_isForbiddenStandaloneUri(cleaned)) {
      return ShareInParseResult.error('share_in_unsupported_type');
    }

    // Reescreve http:// explícito → https:// (alinhado a MessageLinkUtils / chat).
    final normalized = _upgradeHttpInText(cleaned);
    if (normalized.isEmpty) {
      return ShareInParseResult.error('share_in_invalid');
    }

    // Se sobrou scheme não-https perigoso como único conteúdo, rejeita.
    if (_containsOnlyBlockedSchemes(normalized)) {
      return ShareInParseResult.error('share_in_invalid');
    }

    final links = MessageLinkUtils.extractLinks(normalized);
    final ms = receivedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final id = intentId.trim().isEmpty
        ? 'local_${ms}_${normalized.hashCode.abs()}'
        : intentId.trim();
    final fingerprint = fingerprintFor(
      text: normalized,
      intentId: id,
      receivedAtMs: ms,
    );

    return ShareInParseResult.ok(
      ShareInPayload(
        intentId: id,
        text: normalized,
        fingerprint: fingerprint,
        receivedAtMs: ms,
        subject: subject.trim(),
        source: source,
        primaryLink: links.isEmpty ? null : links.first,
      ),
    );
  }

  static String sanitizeSharedText(String input) {
    var s = input.replaceAll('\u0000', ' ').trim();
    // Remove tags HTML simples de shares text/html.
    if (s.contains('<') && s.contains('>')) {
      s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    }
    s = s.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    s = s.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    return s.trim();
  }

  static String fingerprintFor({
    required String text,
    required String intentId,
    required int receivedAtMs,
  }) {
    final material = '$intentId|${text.trim()}|$receivedAtMs';
    // FNV-1a 64-bit — sem dependência nova; suficiente para dedup local.
    var hash = 0xcbf29ce484222325;
    for (final b in utf8.encode(material)) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String _combineSubjectAndText({
    required String subject,
    required String text,
  }) {
    final t = text.trim();
    final s = subject.trim();
    if (s.isEmpty) return t;
    if (t.isEmpty) return s;
    if (t.toLowerCase().contains(s.toLowerCase())) return t;
    return '$s\n$t';
  }

  static int _readMs(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? DateTime.now().millisecondsSinceEpoch;
  }

  static bool _isForbiddenUri(String uri) {
    if (uri.isEmpty) return false;
    final lower = uri.toLowerCase();
    return lower.startsWith('content:') ||
        lower.startsWith('file:') ||
        lower.startsWith('blob:') ||
        lower.startsWith('data:') ||
        lower.startsWith('intent:');
  }

  static bool _isForbiddenStandaloneUri(String text) {
    final t = text.trim().toLowerCase();
    if (_isForbiddenUri(t)) return true;
    if (t.startsWith('javascript:') ||
        t.startsWith('mailto:') ||
        t.startsWith('tel:') ||
        t.startsWith('sms:')) {
      return true;
    }
    return false;
  }

  static String _upgradeHttpInText(String text) {
    return text.replaceAllMapped(
      RegExp(r'\bhttp://([^\s<>"]+)', caseSensitive: false),
      (m) {
        final rest = m.group(1) ?? '';
        final upgraded = MessageLinkUtils.normalizeToHttps('https://$rest');
        return upgraded ?? 'https://$rest';
      },
    );
  }

  static bool _containsOnlyBlockedSchemes(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return true;
    // Texto normal com palavras → ok.
    if (!t.contains(':')) return false;
    final scheme = RegExp(r'^([a-z][a-z0-9+.-]*):').firstMatch(t);
    if (scheme == null) return false;
    final name = scheme.group(1)!;
    if (name == 'https') return false;
    if (name == 'http') return false; // já upgradado
    return MessageLinkUtils.blockedSchemes.contains(name);
  }
}
