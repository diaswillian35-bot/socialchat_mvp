import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/pages/country_people_page.dart';
import 'package:socialchat_mvp/services/admin_access.dart';
import 'package:socialchat_mvp/services/dm_quota_config.dart';
import 'package:socialchat_mvp/services/dm_reply_quota.dart';
import 'package:socialchat_mvp/services/remdy_launch_access.dart';

void main() {
  tearDown(() => AdminAccess.instance.debugSet(admin: false));

  group('Conheça Pessoas: BR, CA e PT para todos', () {
    for (final home in ['br', 'ca', '']) {
      for (final target in ['br', 'ca', 'pt']) {
        test('home="$home" abre $target', () {
          expect(
            RemdyLaunchAccess.canBrowseCountryPeople(
              userHomeCountryCode: home,
              targetCountryCode: target,
            ),
            isTrue,
          );
        });
      }
    }
    test('mundo/país fora da lista continua fechado para não-admin', () {
      expect(
        RemdyLaunchAccess.canBrowseCountryPeople(
          userHomeCountryCode: 'br',
          targetCountryCode: 'us',
        ),
        isFalse,
      );
    });
    test('Home usa o gate de pessoas (bug: Canadá "não disponível")', () {
      final home = File('lib/pages/home_page.dart').readAsStringSync();
      expect(home, contains('canBrowseCountryPeople'));
      expect(home, isNot(contains('canAccessCountryContent')));
    });
  });

  group('Admin total', () {
    test('e-mail verificado ou login Google com o e-mail do Willian', () {
      expect(
        AdminAccess.isAdminUser(
          email: 'diaswillian35@gmail.com',
          emailVerified: true,
        ),
        isTrue,
      );
      expect(
        AdminAccess.isAdminUser(
          email: 'diaswillian35@gmail.com',
          emailVerified: false,
          providers: const [
            MapEntry('google.com', 'DiasWillian35@gmail.com'),
          ],
        ),
        isTrue,
      );
      expect(
        AdminAccess.isAdminUser(
          email: 'diaswillian35@gmail.com',
          emailVerified: false,
          providers: const [
            MapEntry('password', 'diaswillian35@gmail.com'),
          ],
        ),
        isFalse,
      );
      expect(
        AdminAccess.isAdminUser(email: 'outro@gmail.com', emailVerified: true),
        isFalse,
      );
    });
    test('admin abre BR, CA, PT em pessoas e grupos', () {
      AdminAccess.instance.debugSet(admin: true);
      for (final c in ['br', 'ca', 'pt']) {
        expect(
          RemdyLaunchAccess.canBrowseCountryPeople(
            userHomeCountryCode: 'br',
            targetCountryCode: c,
          ),
          isTrue,
        );
        expect(
          RemdyLaunchAccess.canAccessCountryContent(
            userHomeCountryCode: 'br',
            targetCountryCode: c,
          ),
          isTrue,
        );
      }
    });
    test('chat do admin sem cota (não usa a franquia)', () {
      final chat = File('lib/pages/chat_page.dart').readAsStringSync();
      expect(chat, contains('!AdminAccess.isAdmin && DmSendPath.requiresCallable'));
    });
  });

  test('cota: 1500 para todos; conversa antiga com limit 300 vira 1500', () {
    final q = DmReplyQuota.fromMap({'freeUid': 'u', 'used': 300, 'limit': 300});
    expect(q.limit, 1500);
    expect(q.remaining, 1200);
    expect(DmReplyQuota.defaultLimit, 1500);
  });

  test('faixa do lançamento: países conforme a origem', () {
    String? k(String v, String c) => CountryPeoplePage.launchBannerKey(
          viewerCountryCode: v,
          targetCountryCode: c,
        );
    expect(k('br', 'br'), isNull);
    expect(k('br', 'ca'), 'launch_free_chat_banner_br');
    expect(k('ca', 'pt'), 'launch_free_chat_banner_ca');
    expect(k('pt', 'br'), 'launch_free_chat_banner_pt');
    expect(k('', 'ca'), 'launch_free_chat_banner');
    for (final l in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final m = File('lib/l10n/$l.json').readAsStringSync();
      for (final key in [
        'launch_free_chat_banner_title',
        'launch_free_chat_banner',
        'launch_free_chat_banner_br',
        'launch_free_chat_banner_ca',
        'launch_free_chat_banner_pt',
        'launch_all_free',
      ]) {
        expect(m, contains('"$key"'), reason: '$l $key');
      }
    }
    expect(File('lib/pages/menu_page.dart').readAsStringSync(),
        contains("t.get('launch_all_free')"));
  });

  test('cota de DM desligada por padrão (appConfig/dmQuota)', () {
    expect(DmQuotaConfig.enabled, isFalse);
    expect(DmQuotaConfig.parseEnabled(null), isFalse);
    expect(DmQuotaConfig.parseEnabled({'enabled': 'true'}), isFalse);
    expect(DmQuotaConfig.parseEnabled({'enabled': true}), isTrue);
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();
    expect(chat, contains('DmQuotaConfig.enabled && !AdminAccess.isAdmin'));
  });
}
