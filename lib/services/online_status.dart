import 'package:cloud_firestore/cloud_firestore.dart';

/// Definição única de “online” para contadores e bolinha verde.
///
/// Online quando:
/// - `isOnline == true` (agregado pelo PresenceService), e
/// - `lastSeenAt` dentro da janela (serverTimestamp + tolerância de rede).
class OnlineStatus {
  OnlineStatus._();

  static const Duration onlineWindow = Duration(seconds: 90);
  static const Duration clockSkewTolerance = Duration(seconds: 45);
  static const Duration queryLookbackExtra = Duration(seconds: 60);

  static DateTime? toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      if (value < 2000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is num) {
      final n = value.toInt();
      if (n < 2000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n * 1000);
      }
      return DateTime.fromMillisecondsSinceEpoch(n);
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// True se o heartbeat ainda é válido em relação a [now].
  static bool isFreshLastSeen(DateTime? lastSeen, DateTime now) {
    if (lastSeen == null) return false;
    final age = now.difference(lastSeen);
    if (age.isNegative) return true;
    return age <= onlineWindow + clockSkewTolerance;
  }

  /// Sessão individual (ou doc agregado) está online.
  static bool isOnline(
    Map<String, dynamic>? data,
    DateTime now,
  ) {
    if (data == null || data.isEmpty) return false;
    if (data['isOnline'] != true) return false;
    final lastSeen = toDateTime(data['lastSeenAt']);
    return isFreshLastSeen(lastSeen, now);
  }

  /// Conta UIDs únicos online a partir de docs `publicUsers` (ou similares).
  static int countUniqueOnline({
    required Iterable<Map<String, dynamic>> docs,
    required DateTime now,
    required String Function(Map<String, dynamic> data) idOf,
    Set<String>? onlyUids,
    Set<String>? excludeUids,
  }) {
    final seen = <String>{};
    for (final data in docs) {
      final id = idOf(data).trim();
      if (id.isEmpty) continue;
      if (onlyUids != null && !onlyUids.contains(id)) continue;
      if (excludeUids != null && excludeUids.contains(id)) continue;
      if (!isOnline(data, now)) continue;
      seen.add(id);
    }
    return seen.length;
  }

  static Timestamp querySince(DateTime now) {
    return Timestamp.fromDate(
      now.subtract(onlineWindow + queryLookbackExtra),
    );
  }

  /// Label “1 online” / “2 online” — [onlineWord] já traduzido.
  static String formatOnlineCount({
    required int count,
    required String onlineWord,
  }) {
    final n = count < 0 ? 0 : count;
    return '$n $onlineWord';
  }
}
