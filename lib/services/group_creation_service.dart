import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

/// Criação segura de grupo via Cloud Function.
class GroupCreationService {
  GroupCreationService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static String newRequestId() => const Uuid().v4();

  /// Retorna `groupId`, `inviteCode` e `created` (false se idempotente).
  static Future<Map<String, dynamic>> createGroup({
    required String requestId,
    required Map<String, dynamic> fields,
  }) async {
    final callable = _functions.httpsCallable('createGroup');
    final result = await callable.call(<String, dynamic>{
      ...fields,
      'requestId': requestId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return data;
  }

  static String errorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'group_create_no_permission';
      case 'unauthenticated':
        return 'create_group_need_login';
      case 'invalid-argument':
        final msg = (e.message ?? '').toLowerCase();
        if (msg.contains('name')) return 'group_edit_name_required';
        if (msg.contains('joinpolicy')) return 'group_edit_invalid_policy';
        if (msg.contains('location') ||
            msg.contains('scope') ||
            msg.contains('latitude') ||
            msg.contains('longitude')) {
          return 'group_edit_invalid_location';
        }
        return 'group_create_error';
      default:
        return 'group_create_error';
    }
  }
}
