import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'share_extension_session_service.dart';

class UserBootstrap {
  static   Future<void> ensureUserDoc({
    String? referredBy, // opcional (convite)
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);

    final snap = await ref.get();
    if (snap.exists && snap.data()?['isBanned'] == true) {
  await ShareExtensionSessionService.revokeLocalAndRemote();
  await FirebaseAuth.instance.signOut();
  throw Exception('ACCOUNT_BANNED');
}



    // dados mínimos (compatível com rules: sem auto-concessão Premium)
    final baseData = <String, dynamic>{
      'uid': uid,
      'email': user.email ?? '',
      'name': user.displayName ?? '',
      'photoUrl': user.photoURL ?? '',
      'createdAt': FieldValue.serverTimestamp(),

      // defaults do app (ajuste se quiser)
      'isPremium': false,
      'isBanned': false,
      'invitesCount': 0,
      'inviteRewardLevel': 0,
      'isAmbassador': false,
      'invitesGoal': 5,
      'lastSeenAt': FieldValue.serverTimestamp(),
      'isOnline': true,
    };

    if (!snap.exists) {
      if (referredBy != null && referredBy.trim().isNotEmpty) {
        baseData['referredBy'] = referredBy.trim();
      }
      await ref.set(baseData, SetOptions(merge: true));
      return;
    }

    // Se já existe, só completa campos que faltam (não sobrescreve uid/email)
    final data = snap.data() ?? {};
    final patch = <String, dynamic>{};

    void putIfMissing(String key, dynamic value) {
      if (!data.containsKey(key) || data[key] == null || (data[key] is String && (data[key] as String).isEmpty)) {
        patch[key] = value;
      }
    }

    putIfMissing('name', user.displayName ?? '');
    putIfMissing('photoUrl', user.photoURL ?? '');
    putIfMissing('email', user.email ?? ''); // só se estiver vazio
    putIfMissing('uid', uid); // só se estiver faltando
    patch['lastSeenAt'] = FieldValue.serverTimestamp();
    patch['isOnline'] = true;

    if (patch.isNotEmpty) {
      await ref.set(patch, SetOptions(merge: true));
    }
  }
}
