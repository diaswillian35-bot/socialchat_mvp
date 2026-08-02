import 'package:cloud_functions/cloud_functions.dart';

/// Promover / rebaixar / remover membros via Cloud Functions.
class GroupRolesService {
  GroupRolesService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<void> promoteAdmin({
    required String groupId,
    required String targetUid,
  }) async {
    final callable = _functions.httpsCallable('promoteGroupAdmin');
    await callable.call(<String, dynamic>{
      'groupId': groupId,
      'targetUid': targetUid,
    });
  }

  static Future<void> demoteAdmin({
    required String groupId,
    required String targetUid,
  }) async {
    final callable = _functions.httpsCallable('demoteGroupAdmin');
    await callable.call(<String, dynamic>{
      'groupId': groupId,
      'targetUid': targetUid,
    });
  }

  static Future<void> removeMember({
    required String groupId,
    required String targetUid,
  }) async {
    final callable = _functions.httpsCallable('removeGroupMember');
    await callable.call(<String, dynamic>{
      'groupId': groupId,
      'targetUid': targetUid,
    });
  }

  static String errorKeyForPromote(FirebaseFunctionsException e) {
    if (e.code == 'permission-denied') return 'group_promote_error';
    return 'group_promote_error';
  }

  static String errorKeyForDemote(FirebaseFunctionsException e) {
    return 'group_demote_error';
  }

  static String errorKeyForRemove(FirebaseFunctionsException e) {
    return 'group_remove_error';
  }
}
