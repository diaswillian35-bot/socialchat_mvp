import 'presence_rtdb_config.dart';

/// Origem sanitizada do contador Home (sem PII).
enum PresenceDisplaySource {
  /// Ainda sem leitura confirmada.
  unknown,

  /// `presenceDisplayCounters/*` fresco e válido.
  neu,

  /// Fallback em `presenceCounters/*`.
  legacy,

  /// Novo path existe mas `updatedAt` velho → usa legado até refrescar.
  stale,
}

/// Decisão pura: new vs legacy (testável sem Firebase).
class PresenceDisplayRollout {
  PresenceDisplayRollout._();

  /// Idade máxima aceitável do publish display (vários intervalos de coalesce).
  static Duration get maxDisplayAge =>
      PresenceRtdbConfig.displayCounterPublishInterval * 5;

  /// Intervalo entre one-shot probes do path novo enquanto no legado.
  static Duration get legacyToNewProbeInterval =>
      PresenceRtdbConfig.connectionHeartbeatInterval;

  /// Avalia se o payload novo é utilizável.
  ///
  /// [updatedAtMs] = `presenceDisplayCounters/updatedAt` (ms epoch).
  /// [counterValue] = valor já parseado do nó world/country (ou null se
  /// o snapshot ainda não chegou / path ausente).
  /// [permissionDenied] = erro de Rules no path novo.
  static PresenceDisplaySource evaluateNewPath({
    required DateTime now,
    int? updatedAtMs,
    bool counterSnapshotReceived = false,
    bool permissionDenied = false,
    Duration? maxAge,
  }) {
    if (permissionDenied) return PresenceDisplaySource.legacy;

    if (!counterSnapshotReceived && updatedAtMs == null) {
      return PresenceDisplaySource.unknown;
    }

    // Path “existe” com contador mas sem updatedAt → tratar como não pronto
    // (backend incompleto) e cair no legado.
    if (updatedAtMs == null) {
      return PresenceDisplaySource.legacy;
    }

    final age = now.difference(
      DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );
    final limit = maxAge ?? maxDisplayAge;
    if (age.isNegative) {
      // Relógio adiantado no client: aceitar como fresco.
      return PresenceDisplaySource.neu;
    }
    if (age > limit) return PresenceDisplaySource.stale;
    return PresenceDisplaySource.neu;
  }

  /// Após avaliar o novo path, qual feed ativo?
  static PresenceDisplaySource feedFor({
    required PresenceDisplaySource evaluation,
  }) {
    switch (evaluation) {
      case PresenceDisplaySource.neu:
        return PresenceDisplaySource.neu;
      case PresenceDisplaySource.stale:
      case PresenceDisplaySource.legacy:
        return PresenceDisplaySource.legacy;
      case PresenceDisplaySource.unknown:
        return PresenceDisplaySource.unknown;
    }
  }

  /// Label sanitizado para logs (`new` | `legacy` | `stale` | `unknown`).
  static String diagLabel(PresenceDisplaySource source) {
    switch (source) {
      case PresenceDisplaySource.neu:
        return 'new';
      case PresenceDisplaySource.legacy:
        return 'legacy';
      case PresenceDisplaySource.stale:
        return 'stale';
      case PresenceDisplaySource.unknown:
        return 'unknown';
    }
  }

  static int? parseUpdatedAtMs(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    if (value is Map) {
      final raw = value['updatedAt'] ?? value['ms'] ?? value['value'];
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw.trim());
    }
    return null;
  }
}
