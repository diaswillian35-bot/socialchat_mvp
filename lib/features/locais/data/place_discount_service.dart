import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../services/functions_error_text.dart';
import '../models/place_discount.dart';

class PlaceDiscountCode {
  const PlaceDiscountCode({
    required this.code,
    required this.payload,
    required this.expiresAt,
    required this.percent,
    required this.promotionId,
  });

  final String code;
  final String payload;
  final DateTime expiresAt;
  final int percent;
  final String promotionId;
}

/// Callables do selo de desconto. O cliente só lê `places/{id}.discount`.
class PlaceDiscountService {
  PlaceDiscountService._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final res = await _fn.httpsCallable(name).call(data);
    final raw = res.data;
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  static String? functionsText(Object error) => functionsErrorText(
        error,
        fallbackKey: 'place_discount_error',
      );

  /// Lê o campo público `discount` (regras já permitem get do doc).
  static Future<PlaceDiscount?> load(String placeId) async {
    if (placeId.isEmpty) return null;
    final snap = await FirebaseFirestore.instance
        .collection('places')
        .doc(placeId)
        .get();
    if (!snap.exists) return null;
    return PlaceDiscount.tryParse(snap.data()?['discount']);
  }

  static Future<void> setOwnerDiscount({
    required String placeId,
    required int percent,
    required DateTime validUntil,
    required bool enabled,
  }) async {
    await _call('setPlaceDiscount', {
      'placeId': placeId,
      'percent': percent,
      'validUntil': validUntil.toUtc().toIso8601String(),
      'enabled': enabled,
    });
  }

  static Future<void> setPartnershipDiscount({
    required String placeId,
    required int percent,
    required DateTime validUntil,
    required bool enabled,
    required String coveredBy,
  }) async {
    await _call('setPlacePartnershipDiscount', {
      'placeId': placeId,
      'percent': percent,
      'validUntil': validUntil.toUtc().toIso8601String(),
      'enabled': enabled,
      'coveredBy': coveredBy,
    });
  }

  static Future<PlaceDiscountCode> issueCode(String placeId) async {
    final data = await _call('issuePlaceDiscountCode', {'placeId': placeId});
    final code = '${data['code'] ?? ''}';
    if (code.isEmpty) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'Discount is not active.',
      );
    }
    final ms = data['expiresAtMs'];
    final expires = ms is num
        ? DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true)
        : DateTime.now().toUtc().add(const Duration(seconds: 60));
    return PlaceDiscountCode(
      code: code,
      payload: '${data['payload'] ?? code}',
      expiresAt: expires,
      percent: data['percent'] is num ? (data['percent'] as num).toInt() : 0,
      promotionId: '${data['promotionId'] ?? ''}',
    );
  }

  static Future<int> redeem({
    required String placeId,
    required String code,
  }) async {
    final data = await _call('redeemPlaceDiscount', {
      'placeId': placeId,
      'code': code,
    });
    return data['percent'] is num ? (data['percent'] as num).toInt() : 0;
  }

  static bool get isLoggedIn => FirebaseAuth.instance.currentUser != null;
}
