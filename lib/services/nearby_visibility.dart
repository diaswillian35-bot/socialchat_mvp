import 'package:cloud_firestore/cloud_firestore.dart';

/// "Não aparecer na minha cidade" = nearbyEnabled false (lógica invertida).
class NearbyVisibility {
  NearbyVisibility._();

  static const String field = 'nearbyEnabled';

  static bool hideInCityFromData(Map<String, dynamic>? data) =>
      data?[field] != true;

  static Map<String, dynamic> payloadForHide(bool hide) => {field: !hide};

  /// Grava em users e publicUsers (mesmos campos do Editar perfil).
  static Future<void> saveHideInCity(String uid, bool hide) async {
    final db = FirebaseFirestore.instance;
    await db.collection('users').doc(uid).set({
      ...payloadForHide(hide),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await db
        .collection('publicUsers')
        .doc(uid)
        .set(payloadForHide(hide), SetOptions(merge: true));
  }
}
