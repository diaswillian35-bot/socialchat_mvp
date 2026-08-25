/// Franquia de resposta Free em DM internacional (300 Unicode scalar values).
///
/// Contagem canônica alinhada a `functions/international_dm_policy.js`:
/// **code points** (`String.runes.length`), não UTF-16 (`length`) nem UTF-8.

import 'international_chat_service.dart';
import 'international_country_codes.dart';

class DmReplyQuota {
  const DmReplyQuota({
    required this.used,
    required this.limit,
    required this.freeUid,
    this.enabled = true,
  });

  static const int defaultLimit = 300;

  final int used;
  final int limit;
  final String freeUid;
  final bool enabled;

  int get remaining => (limit - used).clamp(0, limit);

  bool get exhausted => remaining <= 0;

  factory DmReplyQuota.fromMap(Map<String, dynamic>? raw, {String? expectFreeUid}) {
    if (raw == null) {
      return const DmReplyQuota(
        used: 0,
        limit: defaultLimit,
        freeUid: '',
        enabled: false,
      );
    }
    final freeUid = (raw['freeUid'] ?? '').toString().trim();
    final used = raw['used'] is int
        ? raw['used'] as int
        : int.tryParse('${raw['used']}') ?? 0;
    final limit = raw['limit'] is int
        ? raw['limit'] as int
        : int.tryParse('${raw['limit']}') ?? defaultLimit;
    final safeLimit = limit < 1 ? defaultLimit : limit;
    // Resposta da Callable pode omitir freeUid; ainda assim sincroniza used/limit.
    final enabled = raw['enabled'] != false &&
        (freeUid.isNotEmpty || raw.containsKey('used') || raw.containsKey('remaining'));
    if (expectFreeUid != null &&
        expectFreeUid.isNotEmpty &&
        freeUid.isNotEmpty &&
        freeUid != expectFreeUid) {
      return DmReplyQuota(
        used: used.clamp(0, safeLimit),
        limit: safeLimit,
        freeUid: freeUid,
        enabled: false,
      );
    }
    return DmReplyQuota(
      used: used.clamp(0, safeLimit),
      limit: safeLimit,
      freeUid: freeUid,
      enabled: enabled,
    );
  }

  /// Unicode scalar values (code points) — espelha JS `codePointAt` loop.
  static int countCodePoints(String text) => text.runes.length;

  bool draftExceeds(String draft) => countCodePoints(draft) > remaining;

  /// Franquia efetiva na UI quando replyQuota ainda não existe no Firestore.
  /// Ausência no servidor = 300 disponíveis para o Free (não zero).
  static DmReplyQuota effectiveForConversation({
    required bool usesReplyQuota,
    required Map<String, dynamic>? replyQuotaRaw,
    required String myUid,
    DmReplyQuota? fromCallable,
  }) {
    if (!usesReplyQuota) {
      return const DmReplyQuota(
        used: 0,
        limit: defaultLimit,
        freeUid: '',
        enabled: false,
      );
    }
    if (fromCallable != null) {
      return fromCallable;
    }
    final parsed = DmReplyQuota.fromMap(
      replyQuotaRaw,
      expectFreeUid: myUid,
    );
    if (parsed.enabled && (parsed.freeUid.isEmpty || parsed.freeUid == myUid)) {
      return parsed;
    }
    return DmReplyQuota(
      used: 0,
      limit: defaultLimit,
      freeUid: myUid,
      enabled: true,
    );
  }

  /// Modal Premium só quando franquia esgotada (used >= limit).
  static bool shouldShowQuotaExhaustedModal({
    required bool usesReplyQuota,
    required DmReplyQuota quota,
  }) {
    if (!usesReplyQuota) return false;
    return quota.exhausted;
  }
}

/// Decisão de path de envio no cliente (servidor revalida).
class DmSendPath {
  /// Callable quando Free e relação ≠ same (internacional ou país unknown).
  static bool requiresCallable({
    required bool senderIsPremium,
    required Map<String, dynamic> senderData,
    required Map<String, dynamic> recipientData,
  }) {
    if (senderIsPremium) return false;
    final rel = InternationalChatService.dmCountryRelation(
      senderData,
      recipientData,
    );
    return rel != DmCountryRelation.same;
  }

  /// Retrocompat — preferir overload com senderData/recipientData.
  static bool requiresCallableLegacy({
    required bool senderIsPremium,
    required bool isInternational,
  }) {
    if (senderIsPremium) return false;
    return isInternational;
  }
}
