import 'package:cloud_functions/cloud_functions.dart';
import '../l10n/app_texts.dart';

String groupRoleErrorText(FirebaseFunctionsException error) {
  const keys = {
    'group_owner_protected',
    'group_admin_protected',
    'group_only_owner_roles',
    'group_role_not_allowed',
    'group_owner_transfer_disabled',
    'group_owner_cannot_leave',
  };
  final details = error.details;
  final key = details is Map ? details['localizationKey'] : error.message;
  return keys.contains(key)
      ? AppTexts.current.get(key as String)
      : (error.message ?? error.code);
}
