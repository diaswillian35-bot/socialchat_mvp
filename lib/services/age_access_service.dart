import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'age_verification.dart';

/// Fail-closed guard used by entry points that can run outside AuthGate.
class AgeAccessService {
  AgeAccessService._();

  static Future<bool> currentUserIsVerified() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return AgeVerification.isVerified(snap.data());
    } catch (_) {
      return false;
    }
  }
}
