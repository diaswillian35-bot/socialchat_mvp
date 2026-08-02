import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Banimento de membros de grupo (callables + checagem de status).
class GroupBanService {
  GroupBanService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> banDoc({
    required String groupId,
    required String uid,
  }) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('bannedUsers')
        .doc(uid);
  }

  /// `true` quando existe ban ativo para o UID no grupo.
  static Future<bool> isUserBanned({
    required String groupId,
    required String uid,
  }) async {
    if (groupId.isEmpty || uid.isEmpty) return false;
    try {
      final snap = await banDoc(groupId: groupId, uid: uid).get();
      if (!snap.exists) return false;
      return snap.data()?['isActive'] == true;
    } catch (_) {
      // Fail-closed: em erro de rede/permissão, trata como banido.
      return true;
    }
  }

  static Future<void> banMember({
    required String groupId,
    required String targetUid,
    String reason = '',
  }) async {
    final callable = _functions.httpsCallable('banGroupMember');
    await callable.call(<String, dynamic>{
      'groupId': groupId,
      'targetUid': targetUid,
      'reason': reason,
    });
  }

  static Future<void> unbanMember({
    required String groupId,
    required String targetUid,
  }) async {
    final callable = _functions.httpsCallable('unbanGroupMember');
    await callable.call(<String, dynamic>{
      'groupId': groupId,
      'targetUid': targetUid,
    });
  }

  static String messageForFunctionsError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'group_login_to_join';
      case 'permission-denied':
        return 'group_ban_error';
      case 'failed-precondition':
        return 'group_ban_error';
      case 'not-found':
        return 'group_unavailable';
      default:
        return 'group_ban_error';
    }
  }

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;
}
