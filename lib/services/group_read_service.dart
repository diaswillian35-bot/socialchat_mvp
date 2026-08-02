import 'package:cloud_functions/cloud_functions.dart';

/// Marca o grupo como lido para o usuário autenticado.
class GroupReadService {
  GroupReadService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<void> markAsRead({required String groupId}) async {
    final callable = _functions.httpsCallable('markGroupAsRead');
    await callable.call(<String, dynamic>{'groupId': groupId});
  }

  static String errorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'failed-precondition':
        return 'group_no_longer_available';
      case 'permission-denied':
        return 'group_read_not_member';
      case 'not-found':
        return 'group_no_longer_available';
      default:
        return 'group_read_update_error';
    }
  }
}
