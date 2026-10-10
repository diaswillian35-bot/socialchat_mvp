import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/services/block_visibility.dart';
import 'package:socialchat_mvp/services/blocked_users_list_logic.dart';

void main() {
  tearDown(() {
    BlockVisibility.debugReplace({});
  });

  String source(String path) => File(path).readAsStringSync();

  test('blocked list is reachable from menu and profile', () {
    final menu = source('lib/pages/menu_page.dart');
    final profile = source('lib/pages/profile_page.dart');
    final page = source('lib/pages/blocked_users_page.dart');
    expect(menu, contains('BlockedUsersPage'));
    expect(menu, contains("t.get('blocked_users_title')"));
    expect(profile, contains('BlockedUsersPage'));
    expect(profile, contains("AppTexts.current.get('blocked_users_title')"));
    expect(page, contains('BlockService.unblockUser'));
    expect(page, contains("collection('users')"));
    expect(page, contains("['blocked']"));
    expect(page, isNot(contains('reports')));
    expect(page, isNot(contains('showComingSoon')));
  });

  test('orderedUids reads users.blocked without inventing ids', () {
    expect(BlockedUsersListLogic.orderedUids(null), isEmpty);
    expect(
      BlockedUsersListLogic.orderedUids([' a ', 'b', 'a', '', 'b']),
      ['a', 'b'],
    );
  });

  test('unblock restores local hide from item 3 without deleting content', () {
    BlockVisibility.debugReplace({'peer'});
    expect(BlockVisibility.hidesUid('peer'), isTrue);
    BlockVisibility.noteUnblocked('peer');
    expect(BlockVisibility.hidesUid('peer'), isFalse);
    expect(
      BlockVisibility.hidesConversation(
        data: {
          'participants': ['me', 'peer'],
          'lastText': 'hello',
        },
        myUid: 'me',
      ),
      isFalse,
    );
    final unblock = source('lib/services/block_service.dart')
        .split('static Future<void> unblockUser')
        .last
        .split('isBlockedStream')
        .first;
    expect(unblock, contains('arrayRemove'));
    expect(unblock, contains('noteUnblocked'));
    expect(unblock, isNot(contains('reports')));
    expect(unblock, isNot(contains('delete')));
  });

  test('five locales translate blocked-users path without coming-soon copy', () {
    final files = {
      'lib/l10n/en.json': 'Blocked users',
      'lib/l10n/pt-BR.json': 'Usuários bloqueados',
      'lib/l10n/pt-PT.json': 'Utilizadores bloqueados',
      'lib/l10n/es.json': 'Usuarios bloqueados',
      'lib/l10n/fr.json': 'Utilisateurs bloqués',
    };
    for (final entry in files.entries) {
      final map = jsonDecode(source(entry.key)) as Map<String, dynamic>;
      expect(map['blocked_users_title'], entry.value);
      expect(map.containsKey('blocked_users_empty'), isTrue);
      expect(map.containsKey('blocked_users_unblock'), isTrue);
      expect(map.containsKey('blocked_users_unblocked'), isTrue);
      final blob =
          '${map['blocked_users_title']} ${map['blocked_users_empty']} '
          '${map['blocked_users_unblock']} ${map['blocked_users_unblocked']}';
      expect(blob.toLowerCase(), isNot(contains('em breve')));
      expect(blob.toLowerCase(), isNot(contains('coming soon')));
    }
    AppTexts.loadFromMap({
      'blocked_users_title': 'Blocked users',
      'blocked_users_unblock': 'Unblock',
    });
    expect(AppTexts.current.get('blocked_users_title'), 'Blocked users');
  });

  test('pubspec stays 1.0.4+35', () {
    expect(source('pubspec.yaml'), contains('version: 1.0.4+35'));
  });
}
