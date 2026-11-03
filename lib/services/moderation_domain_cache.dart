import 'package:cloud_firestore/cloud_firestore.dart';

import 'objectionable_content_filter.dart';

/// Lê `appConfig/moderation.blockedDomains` uma vez por sessão.
/// Falha de rede não impede o envio: a lista embutida continua valendo
/// e o servidor aplica a config atual.
class ModerationDomainCache {
  ModerationDomainCache._();

  static bool _loaded = false;

  static Future<void> ensureLoaded({FirebaseFirestore? firestore}) async {
    if (_loaded) return;
    try {
      final db = firestore ?? FirebaseFirestore.instance;
      final snap = await db.doc('appConfig/moderation').get();
      final raw = snap.data()?['blockedDomains'];
      if (raw is List) {
        ObjectionableContentFilter.setBlockedDomains(
          raw.map((e) => e.toString()).toList(),
        );
      }
    } catch (_) {}
    _loaded = true;
  }
}
