import 'package:cloud_firestore/cloud_firestore.dart';

import 'explore_only.dart';

/// Tela de boas-vindas do 1º acesso (uma vez por usuário):
/// users/{uid}.welcomeChoiceDone.
class WelcomeChoice {
  WelcomeChoice._();

  static const String field = 'welcomeChoiceDone';

  /// Mostra só para perfil completo que ainda não escolheu.
  static bool needsChoice(Map<String, dynamic>? data) =>
      data != null && data['profileComplete'] == true && data[field] != true;

  /// Grava a escolha (exploreOnly nos dois docs + presença) e marca a flag.
  static Future<void> complete(String uid, {required bool exploreOnly}) async {
    await ExploreOnly.setMode(uid, exploreOnly);
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      field: true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
