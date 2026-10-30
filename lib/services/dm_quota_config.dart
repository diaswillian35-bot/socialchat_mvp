import 'package:cloud_firestore/cloud_firestore.dart';

/// Cota de caracteres em DM entre países — configurável no servidor.
///
/// Documento `appConfig/dmQuota` `{ enabled: bool, limit: int }`.
/// Ausente ou `enabled != true` → DESLIGADA (lançamento: tudo grátis e sem
/// limite). As Functions (sendDmMessage) leem o mesmo documento.
class DmQuotaConfig {
  DmQuotaConfig._();

  static const String collection = 'appConfig';
  static const String docId = 'dmQuota';

  static bool _enabled = false;

  /// Síncrono; false até o servidor dizer o contrário.
  static bool get enabled => _enabled;

  static bool parseEnabled(Map<String, dynamic>? data) =>
      data != null && data['enabled'] == true;

  static Future<void> load({FirebaseFirestore? firestore}) async {
    try {
      final snap = await (firestore ?? FirebaseFirestore.instance)
          .collection(collection)
          .doc(docId)
          .get();
      _enabled = parseEnabled(snap.data());
    } catch (_) {
      _enabled = false;
    }
  }

  static void debugSet(bool value) => _enabled = value;
}
