import 'package:cloud_functions/cloud_functions.dart';

/// Saída e exclusão lógica de grupos via Cloud Functions.
class GroupLifecycleService {
  GroupLifecycleService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<void> leaveGroup({required String groupId}) async {
    final callable = _functions.httpsCallable('leaveGroup');
    await callable.call(<String, dynamic>{'groupId': groupId});
  }

  static Future<void> transferOwnership({
    required String groupId,
    required String newOwnerUid,
  }) async {
    final callable = _functions.httpsCallable('transferGroupOwnership');
    await callable.call(<String, dynamic>{
      'groupId': groupId,
      'newOwnerUid': newOwnerUid,
    });
  }

  static Future<void> deleteGroup({required String groupId}) async {
    final callable = _functions.httpsCallable('deleteGroup');
    await callable.call(<String, dynamic>{'groupId': groupId});
  }

  static String leaveErrorKey(FirebaseFunctionsException e) {
    if (e.code == 'failed-precondition') {
      final msg = (e.message ?? '').toLowerCase();
      if (msg.contains('owner')) return 'group_owner_cannot_leave';
    }
    return 'group_leave_error';
  }

  static String transferErrorKey(FirebaseFunctionsException e) {
    if (e.code == 'permission-denied') return 'group_transfer_no_permission';
    if (e.code == 'failed-precondition') return 'group_transfer_invalid';
    if (e.code == 'not-found') return 'group_transfer_invalid';
    return 'group_transfer_error';
  }

  static String deleteErrorKey(FirebaseFunctionsException e) {
    return 'group_delete_error';
  }
}
