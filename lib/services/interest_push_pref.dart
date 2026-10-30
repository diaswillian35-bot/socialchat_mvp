import 'package:cloud_firestore/cloud_firestore.dart';

/// users/{uid}.interestPushEnabled (ligado por padrão).
class InterestPushPref {
  InterestPushPref._();

  static const String field = 'interestPushEnabled';

  static bool enabledFromData(Map<String, dynamic>? data) =>
      data?[field] != false;

  static Future<void> save(String uid, bool enabled) =>
      FirebaseFirestore.instance.collection('users').doc(uid).set({
        field: enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}
