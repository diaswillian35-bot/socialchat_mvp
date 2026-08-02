import 'package:cloud_functions/cloud_functions.dart';

/// Atualização segura de configurações do grupo.
class GroupSettingsService {
  GroupSettingsService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<void> updateSettings({
    required String groupId,
    required Map<String, dynamic> changes,
  }) async {
    final callable = _functions.httpsCallable('updateGroupSettings');
    await callable.call(<String, dynamic>{
      'groupId': groupId,
      'changes': changes,
    });
  }

  static String errorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'group_edit_no_permission';
      case 'failed-precondition':
        return 'group_no_longer_available';
      case 'invalid-argument':
        final msg = (e.message ?? '').toLowerCase();
        if (msg.contains('name')) return 'group_edit_name_required';
        if (msg.contains('joinpolicy')) return 'group_edit_invalid_policy';
        if (msg.contains('location') || msg.contains('scope')) {
          return 'group_edit_invalid_location';
        }
        return 'group_edit_error';
      default:
        return 'group_edit_error';
    }
  }
}
