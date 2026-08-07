import 'online_status.dart';
import 'presence_rtdb_config.dart';

/// Interpretação pura de nós RTDB + política de contadores/grupos.
class PresenceRtdbLogic {
  PresenceRtdbLogic._();

  /// Online se existe ≥1 conexão com timestamp fresco.
  /// Números = `ServerValue.timestamp` (ms). Bool/Map legado só contam se
  /// [allowLegacyWithoutTimestamp] (default false — evita fantasma eterno).
  static bool isOnlineFromConnections(
    dynamic connections, {
    DateTime? now,
    Duration? staleAfter,
    bool allowLegacyWithoutTimestamp = false,
  }) {
    return countFreshConnections(
          connections,
          now: now,
          staleAfter: staleAfter,
          allowLegacyWithoutTimestamp: allowLegacyWithoutTimestamp,
        ) >
        0;
  }

  static int countFreshConnections(
    dynamic connections, {
    DateTime? now,
    Duration? staleAfter,
    bool allowLegacyWithoutTimestamp = false,
  }) {
    if (connections == null || connections is! Map || connections.isEmpty) {
      return 0;
    }
    final clock = now ?? DateTime.now();
    final maxAge = staleAfter ?? PresenceRtdbConfig.connectionStaleAfter;
    var n = 0;
    for (final entry in connections.entries) {
      final v = entry.value;
      if (v == null) continue;
      if (v is num) {
        final ts = DateTime.fromMillisecondsSinceEpoch(v.toInt());
        final age = clock.difference(ts);
        if (age.isNegative || age <= maxAge) n++;
        continue;
      }
      if (allowLegacyWithoutTimestamp) {
        if (v is bool && v) n++;
        if (v is Map) n++;
      }
    }
    return n;
  }

  static int countConnections(dynamic connections) {
    return countFreshConnections(
      connections,
      allowLegacyWithoutTimestamp: true,
    );
  }

  /// Transição zero↔uma conexão por UID (evita dupla contagem multi-aparelho).
  static PresenceCounterDelta counterDelta({
    required int connectionsBefore,
    required int connectionsAfter,
  }) {
    final wasOnline = connectionsBefore > 0;
    final isOnline = connectionsAfter > 0;
    if (!wasOnline && isOnline) return PresenceCounterDelta.enter;
    if (wasOnline && !isOnline) return PresenceCounterDelta.leave;
    return PresenceCounterDelta.none;
  }

  /// Conexão antiga e nova são caminhos distintos → onDisconnect antigo
  /// não remove a nova.
  static bool oldDisconnectCanRemoveNew({
    required String oldConnectionId,
    required String newConnectionId,
  }) {
    if (oldConnectionId.isEmpty || newConnectionId.isEmpty) return true;
    return oldConnectionId == newConnectionId;
  }

  static int countOnlineUids({
    required Map<String, dynamic> presenceByUid,
    Set<String>? onlyUids,
    Set<String>? excludeUids,
  }) {
    final seen = <String>{};
    for (final e in presenceByUid.entries) {
      final uid = e.key.trim();
      if (uid.isEmpty) continue;
      if (onlyUids != null && !onlyUids.contains(uid)) continue;
      if (excludeUids != null && excludeUids.contains(uid)) continue;
      final online = e.value is bool
          ? e.value == true
          : isOnlineFromConnections(e.value);
      if (online) seen.add(uid);
    }
    return seen.length;
  }

  static Set<String> capMemberWatches(
    Iterable<String> memberIds, {
    required String? prioritizeUid,
    int max = PresenceRtdbConfig.maxGroupPresenceWatches,
  }) {
    final out = <String>{};
    if (prioritizeUid != null && prioritizeUid.isNotEmpty) {
      out.add(prioritizeUid);
    }
    for (final id in memberIds) {
      final t = id.trim();
      if (t.isEmpty) continue;
      out.add(t);
      if (out.length >= max) break;
    }
    return out;
  }

  /// Exibição de contagem de grupo (nunca parcial como se fosse total).
  static GroupOnlineDisplay groupOnlineDisplay({
    required int memberCount,
    required int watchedOnlineCount,
    required int watchedMemberCount,
    int maxWatches = PresenceRtdbConfig.maxGroupPresenceWatches,
  }) {
    final isLarge = memberCount > maxWatches;
    if (!isLarge) {
      return GroupOnlineDisplay(
        count: watchedOnlineCount,
        isPartial: false,
        watchedMembers: watchedMemberCount,
        totalMembers: memberCount,
      );
    }
    return GroupOnlineDisplay(
      count: watchedOnlineCount,
      isPartial: true,
      watchedMembers: watchedMemberCount,
      totalMembers: memberCount,
    );
  }

  static int parseCounter(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value < 0 ? 0 : value;
    if (value is num) {
      final n = value.toInt();
      return n < 0 ? 0 : n;
    }
    // Resiliência: se o nó for mapa `{count: N}` (formato legado/errado).
    if (value is Map) {
      final raw = value['count'] ?? value['n'] ?? value['value'];
      if (raw is num) {
        final n = raw.toInt();
        return n < 0 ? 0 : n;
      }
    }
    if (value is String) {
      final n = int.tryParse(value.trim());
      if (n != null) return n < 0 ? 0 : n;
    }
    return 0;
  }

  /// Home “mundo” = total mundial − país do usuário (duas linhas sem overlap).
  /// Retorna null enquanto qualquer lado ainda não chegou (evita flash errado).
  static int? worldMinusCountry({
    required int? world,
    required int? country,
  }) {
    if (world == null || country == null) return null;
    final v = world - country;
    return v < 0 ? 0 : v;
  }

  static bool legacyFirestoreOnline(Map<String, dynamic>? data, DateTime now) {
    return OnlineStatus.isOnline(data, now);
  }
}

enum PresenceCounterDelta { none, enter, leave }

class GroupOnlineDisplay {
  const GroupOnlineDisplay({
    required this.count,
    required this.isPartial,
    required this.watchedMembers,
    required this.totalMembers,
  });

  final int count;
  final bool isPartial;
  final int watchedMembers;
  final int totalMembers;

  /// Label: exact `"N online"` ou parcial `"N+ online"`.
  String format({
    required String onlineWord,
    required String Function(int count) partialFormatter,
  }) {
    if (!isPartial) {
      return OnlineStatus.formatOnlineCount(count: count, onlineWord: onlineWord);
    }
    return partialFormatter(count);
  }
}
