import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Fonte única de verdade para acesso Premium no app.
///
/// Acesso ativo quando qualquer condição for verdadeira:
/// 1. `isMaster == true`
/// 2. `isPremium == true`
/// 3. `premiumUntil` é uma data futura
///
/// `premiumType` NÃO decide acesso — apenas indica origem do benefício.
class PremiumAccessService {
  PremiumAccessService._();

  /// Converte `premiumUntil` (Timestamp, DateTime, etc.) sem lançar exceção.
  static DateTime? parsePremiumUntil(dynamic raw) {
    if (raw == null) return null;

    if (raw is Timestamp) {
      try {
        return raw.toDate();
      } catch (_) {
        return null;
      }
    }

    if (raw is DateTime) return raw;

    if (raw is int) {
      // millis ou seconds
      if (raw > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(raw);
      }
      if (raw > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
      }
      return null;
    }

    if (raw is num) {
      return parsePremiumUntil(raw.toInt());
    }

    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      return DateTime.tryParse(trimmed);
    }

    return null;
  }

  /// Regra oficial de acesso Premium a partir dos dados do usuário.
  static bool isPremiumActiveFromData(
    Map<String, dynamic>? data, {
    DateTime? now,
  }) {
    if (data == null || data.isEmpty) return false;

    if (data['isMaster'] == true) return true;
    if (data['isPremium'] == true) return true;

    final until = parsePremiumUntil(data['premiumUntil']);
    if (until == null) return false;

    final reference = now ?? DateTime.now();
    return until.isAfter(reference);
  }

  /// Data de validade futura, se houver (mesmo com `isPremium`/`isMaster`).
  static DateTime? premiumUntilFromData(Map<String, dynamic>? data) {
    return parsePremiumUntil(data?['premiumUntil']);
  }

  /// `premiumUntil` ainda no futuro (independente de isPremium/isMaster).
  static bool hasActiveTimePremium(
    Map<String, dynamic>? data, {
    DateTime? now,
  }) {
    final until = parsePremiumUntil(data?['premiumUntil']);
    if (until == null) return false;
    final reference = now ?? DateTime.now();
    return until.isAfter(reference);
  }

  static Future<Map<String, dynamic>?> fetchCurrentUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;

    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!snap.exists) return null;
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isCurrentUserPremiumActive({DateTime? now}) async {
    final data = await fetchCurrentUserData();
    return isPremiumActiveFromData(data, now: now);
  }
}
