/// Franquia de resposta Free em DM internacional (300 Unicode scalar values).
///
/// Contagem canônica alinhada a `functions/dm_reply_quota.js`:
/// **code points** (`String.runes.length`), não UTF-16 (`length`) nem UTF-8.

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
}

/// Decisão de path de envio no cliente (servidor revalida).
class DmSendPath {
  static bool requiresCallable({
    required bool senderIsPremium,
    required bool isInternational,
  }) {
    if (senderIsPremium) return false;
    return isInternational;
  }
}
