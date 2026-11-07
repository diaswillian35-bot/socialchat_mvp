import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../lib/l10n/app_texts.dart';
import '../lib/services/group_role_error.dart';
import '../lib/services/group_role_policy.dart';

void main() {
  final group = <String, dynamic>{
    'ownerId': 'owner',
    'admins': ['owner', 'admin', 'admin2'],
    'moderators': ['mod', 'mod2'],
    'members': ['owner', 'admin', 'admin2', 'mod', 'mod2', 'member', 'member2']
  };
  const roles = ['owner', 'admin', 'mod', 'member', 'outsider'];
  for (final actor in roles) {
    for (final target in roles) {
      for (final action in ['promote', 'demote', 'remove', 'ban']) {
        test('$actor -> $target: $action', () {
          final expected = target != 'owner' &&
              actor != target &&
              (actor == 'owner' ||
                  ((action == 'remove' || action == 'ban') &&
                      ((actor == 'admin' && target != 'admin') ||
                          (actor == 'mod' && target == 'member'))));
          expect(
              GroupRolePolicy.can(group, actor,
                  target == 'owner' ? target : '${target}2', action),
              expected);
        });
      }
    }
  }
  for (final locale in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
    test('policy copy in $locale', () {
      final texts = jsonDecode(File('lib/l10n/$locale.json').readAsStringSync())
          as Map<String, dynamic>;
      AppTexts.loadFromMap(texts);
      for (final key in [
        'group_owner_protected',
        'group_admin_protected',
        'group_only_owner_roles',
        'group_role_not_allowed',
        'group_owner_transfer_disabled',
        'group_owner_cannot_leave',
        'group_role_moderator',
        'group_promote_moderator',
        'group_promote_moderator_confirm'
      ]) {
        expect(texts[key], isA<String>());
        expect((texts[key] as String).trim(), isNotEmpty);
        if (key != 'group_role_moderator' &&
            key != 'group_promote_moderator' &&
            key != 'group_promote_moderator_confirm') {
          final error = FirebaseFunctionsException(
              code: 'permission-denied',
              message: key,
              details: {'localizationKey': key});
          expect(groupRoleErrorText(error), AppTexts.t(key));
        }
      }
    });
  }
}
