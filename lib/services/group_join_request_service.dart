import 'package:cloud_functions/cloud_functions.dart';

/// Aprovação e rejeição de pedidos via Cloud Functions.
class GroupJoinRequestService {
  GroupJoinRequestService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<void> approveRequest({
    required String groupId,
    required String requestUid,
  }) async {
    final callable = _functions.httpsCallable('approveGroupJoinRequest');
    await callable.call(<String, dynamic>{
      'groupId': groupId,
      'requestUid': requestUid,
    });
  }

  static Future<void> rejectRequest({
    required String groupId,
    required String requestUid,
    String? reason,
  }) async {
    final callable = _functions.httpsCallable('rejectGroupJoinRequest');
    final payload = <String, dynamic>{
      'groupId': groupId,
      'requestUid': requestUid,
    };
    final r = (reason ?? '').trim();
    if (r.isNotEmpty) {
      payload['reason'] = r;
    }
    await callable.call(payload);
  }

  static String approveErrorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'failed-precondition':
        final msg = (e.message ?? '').toLowerCase();
        if (msg.contains('not pending')) {
          return 'group_join_request_not_pending';
        }
        if (msg.contains('does not accept') || msg.contains('join requests')) {
          return 'group_join_requests_not_accepted';
        }
        if (msg.contains('banned') || msg.contains('cannot join')) {
          return 'group_join_request_user_blocked';
        }
        if (msg.contains('unavailable')) {
          return 'group_no_longer_available';
        }
        return 'group_join_approve_error';
      case 'permission-denied':
        return 'group_join_approve_error';
      case 'not-found':
        return 'group_join_request_not_pending';
      default:
        return 'group_join_approve_error';
    }
  }

  static String rejectErrorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'failed-precondition':
        final msg = (e.message ?? '').toLowerCase();
        if (msg.contains('not pending')) {
          return 'group_join_request_not_pending';
        }
        if (msg.contains('unavailable')) {
          return 'group_no_longer_available';
        }
        return 'group_join_reject_error';
      case 'permission-denied':
        return 'group_join_reject_error';
      case 'not-found':
        return 'group_join_request_not_pending';
      default:
        return 'group_join_reject_error';
    }
  }
}
