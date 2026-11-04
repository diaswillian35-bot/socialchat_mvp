import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socialchat_mvp/services/app_review_prompt.dart';
import 'package:socialchat_mvp/services/install_group_attribution.dart';
import 'package:socialchat_mvp/services/pending_group_code.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final freshInstall = DateTime.utc(2026, 11, 4, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PendingGroupCodeLogic — referrer Android', () {
    test('invite=código e invite codificado', () {
      expect(
        PendingGroupCodeLogic.codeFromInstallReferrer('invite=abC123'),
        'ABC123',
      );
      expect(
        PendingGroupCodeLogic.codeFromInstallReferrer('invite%3Dzz99'),
        'ZZ99',
      );
      expect(
        PendingGroupCodeLogic.codeFromInstallReferrer(
          'invite=ABC123&utm_source=web',
        ),
        'ABC123',
      );
    });

    test('invite pode ser o próprio link', () {
      expect(
        PendingGroupCodeLogic.codeFromInstallReferrer(
          'invite=https%3A%2F%2Fremdy.app%2Fg%2Fcode01',
        ),
        'CODE01',
      );
    });

    test('sem invite, código curto ou lixo não grava', () {
      expect(
        PendingGroupCodeLogic.codeFromInstallReferrer('utm_source=google'),
        isNull,
      );
      expect(
        PendingGroupCodeLogic.codeFromInstallReferrer('invite=ab'),
        isNull,
      );
      expect(PendingGroupCodeLogic.codeFromInstallReferrer(''), isNull);
      expect(PendingGroupCodeLogic.codeFromInstallReferrer(null), isNull);
    });
  });

  group('PendingGroupCodeLogic — área de transferência iOS', () {
    test('link remdy.app/g e prefixo REMDY-', () {
      expect(
        PendingGroupCodeLogic.codeFromIosClipboard(
          'https://remdy.app/g/abc123',
        ),
        'ABC123',
      );
      expect(
        PendingGroupCodeLogic.codeFromIosClipboard(
          '  http://www.remdy.app/g/abc123/  ',
        ),
        'ABC123',
      );
      expect(
        PendingGroupCodeLogic.codeFromIosClipboard('remdy://g/abc123'),
        'ABC123',
      );
      expect(
        PendingGroupCodeLogic.codeFromIosClipboard('REMDY-abc123'),
        'ABC123',
      );
      expect(
        PendingGroupCodeLogic.codeFromIosClipboard(
          'remdy-https://remdy.app/g/zz99',
        ),
        'ZZ99',
      );
    });

    test('texto que não é o convite não é lido', () {
      expect(PendingGroupCodeLogic.codeFromIosClipboard('ABC123'), isNull);
      expect(PendingGroupCodeLogic.codeFromIosClipboard('senha-123'), isNull);
      expect(
        PendingGroupCodeLogic.codeFromIosClipboard(
          'https://evil.com/g/ABC123',
        ),
        isNull,
      );
      expect(
        PendingGroupCodeLogic.codeFromIosClipboard('REMDY-'),
        isNull,
      );
      expect(
        PendingGroupCodeLogic.codeFromIosClipboard('REMDY-no'),
        isNull,
      );
    });
  });

  group('PendingGroupCodeLogic — campo manual', () {
    test('código puro, link e intent://', () {
      expect(PendingGroupCodeLogic.codeFromUserInput(' ab12 '), 'AB12');
      expect(
        PendingGroupCodeLogic.codeFromUserInput('remdy.app/g/abc123'),
        'ABC123',
      );
      expect(
        PendingGroupCodeLogic.codeFromUserInput(
          'intent://remdy.app/g/abc123#Intent;scheme=https;package=com.remdy.app;end',
        ),
        'ABC123',
      );
      expect(PendingGroupCodeLogic.codeFromUserInput('REMDY-qq11'), 'QQ11');
    });

    test('rejeita vazio, curto e host estranho', () {
      expect(PendingGroupCodeLogic.codeFromUserInput('  '), isNull);
      expect(PendingGroupCodeLogic.codeFromUserInput('ab'), isNull);
      expect(
        PendingGroupCodeLogic.codeFromUserInput('https://evil.com/g/ABC123'),
        isNull,
      );
    });
  });

  group('PendingGroupCodeLogic — sobrevive ao cadastro', () {
    test('não abre sem sessão, com e-mail pendente, sem 18+ ou sem foto', () {
      expect(
        PendingGroupCodeLogic.mayOpenPendingGroup(
          hasUser: false,
          needsEmailVerification: false,
          ageVerified: true,
          needsProfilePhoto: false,
        ),
        isFalse,
      );
      expect(
        PendingGroupCodeLogic.mayOpenPendingGroup(
          hasUser: true,
          needsEmailVerification: true,
          ageVerified: true,
          needsProfilePhoto: false,
        ),
        isFalse,
      );
      expect(
        PendingGroupCodeLogic.mayOpenPendingGroup(
          hasUser: true,
          needsEmailVerification: false,
          ageVerified: false,
          needsProfilePhoto: false,
        ),
        isFalse,
      );
      expect(
        PendingGroupCodeLogic.mayOpenPendingGroup(
          hasUser: true,
          needsEmailVerification: false,
          ageVerified: true,
          needsProfilePhoto: true,
        ),
        isFalse,
      );
    });

    test('abre só com cadastro completo, inclusive 18+', () {
      expect(
        PendingGroupCodeLogic.mayOpenPendingGroup(
          hasUser: true,
          needsEmailVerification: false,
          ageVerified: true,
          needsProfilePhoto: false,
        ),
        isTrue,
      );
    });

    test('a chave só sai se a prévia continuou montada', () {
      expect(
        PendingGroupCodeLogic.shouldReleasePendingCode(
          pageStillMounted: false,
        ),
        isFalse,
      );
      expect(
        PendingGroupCodeLogic.shouldReleasePendingCode(
          pageStillMounted: true,
        ),
        isTrue,
      );
    });

    test('install não substitui um código que já está pendente', () {
      expect(
        PendingGroupCodeLogic.installCodeToWrite(
          extracted: 'NEW123',
          alreadyPending: 'OLD123',
        ),
        isNull,
      );
      expect(
        PendingGroupCodeLogic.installCodeToWrite(
          extracted: 'new123',
          alreadyPending: '',
        ),
        'NEW123',
      );
    });
  });

  group('InstallGroupAttribution', () {
    test('Android: referrer recente grava uma vez e não repete', () async {
      SharedPreferences.setMockInitialValues({
        PendingGroupCodeLogic.firstLaunchKey:
            freshInstall.millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      var reads = 0;
      Future<AndroidReferrerRead> read() async {
        reads++;
        return AndroidReferrerRead(
          referrer: 'invite=abc123',
          installBeginTimestampSeconds:
              freshInstall.millisecondsSinceEpoch ~/ 1000,
        );
      }

      await InstallGroupAttribution.captureIfNeeded(
        isAndroid: true,
        isIos: false,
        readAndroidReferrer: read,
        readClipboard: () async => 'https://remdy.app/g/OTHER1',
        clearClipboard: () async {},
        clock: () => freshInstall,
        preferences: prefs,
      );
      expect(prefs.getString(PendingGroupCodeLogic.pendingKey), 'ABC123');
      expect(prefs.getBool(PendingGroupCodeLogic.androidCheckedKey), isTrue);
      expect(reads, 1);

      await InstallGroupAttribution.captureIfNeeded(
        isAndroid: true,
        isIos: false,
        readAndroidReferrer: () async {
          reads++;
          return const AndroidReferrerRead(referrer: 'invite=ZZZZ99');
        },
        readClipboard: () async => null,
        clearClipboard: () async {},
        clock: () => freshInstall,
        preferences: prefs,
      );
      expect(reads, 1);
      expect(prefs.getString(PendingGroupCodeLogic.pendingKey), 'ABC123');
    });

    test('carimbo em milissegundos também conta como instalação recente', () {
      final now = freshInstall.millisecondsSinceEpoch ~/ 1000;
      expect(
        PendingGroupCodeLogic.isRecentPlayInstall(
          installBeginTimestampSeconds: freshInstall.millisecondsSinceEpoch,
          nowSeconds: now,
        ),
        isTrue,
      );
      final old = freshInstall.subtract(const Duration(days: 40));
      expect(
        PendingGroupCodeLogic.isRecentPlayInstall(
          installBeginTimestampSeconds: old.millisecondsSinceEpoch,
          nowSeconds: now,
        ),
        isFalse,
      );
    });

    test('Android: instalação antiga não reabre convite', () async {
      final prefs = await SharedPreferences.getInstance();
      final old = freshInstall.subtract(const Duration(days: 40));
      await InstallGroupAttribution.captureIfNeeded(
        isAndroid: true,
        isIos: false,
        readAndroidReferrer: () async => AndroidReferrerRead(
          referrer: 'invite=OLD123',
          installBeginTimestampSeconds: old.millisecondsSinceEpoch ~/ 1000,
        ),
        readClipboard: () async => null,
        clearClipboard: () async {},
        clock: () => freshInstall,
        preferences: prefs,
      );
      expect(prefs.getString(PendingGroupCodeLogic.pendingKey), isNull);
      expect(prefs.getBool(PendingGroupCodeLogic.androidCheckedKey), isTrue);
    });

    test('Android: falha transitória não marca como lido', () async {
      final prefs = await SharedPreferences.getInstance();
      await InstallGroupAttribution.captureIfNeeded(
        isAndroid: true,
        isIos: false,
        readAndroidReferrer: () async => const AndroidReferrerRead(
          definitive: false,
        ),
        readClipboard: () async => null,
        clearClipboard: () async {},
        clock: () => freshInstall,
        preferences: prefs,
      );
      expect(
          prefs.getBool(PendingGroupCodeLogic.androidCheckedKey), isNot(true));
      expect(prefs.getString(PendingGroupCodeLogic.pendingKey), isNull);
    });

    test('Android: não substitui pending_group_code existente', () async {
      SharedPreferences.setMockInitialValues({
        PendingGroupCodeLogic.pendingKey: 'KEEP01',
      });
      final prefs = await SharedPreferences.getInstance();
      await InstallGroupAttribution.captureIfNeeded(
        isAndroid: true,
        isIos: false,
        readAndroidReferrer: () async => AndroidReferrerRead(
          referrer: 'invite=NEW999',
          installBeginTimestampSeconds:
              freshInstall.millisecondsSinceEpoch ~/ 1000,
        ),
        readClipboard: () async => null,
        clearClipboard: () async {},
        clock: () => freshInstall,
        preferences: prefs,
      );
      expect(prefs.getString(PendingGroupCodeLogic.pendingKey), 'KEEP01');
    });

    test('iOS: link no primeiro uso grava e limpa a área de transferência',
        () async {
      SharedPreferences.setMockInitialValues({
        PendingGroupCodeLogic.firstLaunchKey:
            freshInstall.millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      var cleared = 0;
      await InstallGroupAttribution.captureIfNeeded(
        isAndroid: false,
        isIos: true,
        readAndroidReferrer: () async => const AndroidReferrerRead(),
        readClipboard: () async => 'https://www.remdy.app/g/ios123',
        clearClipboard: () async {
          cleared++;
        },
        clock: () => freshInstall,
        preferences: prefs,
      );
      expect(prefs.getString(PendingGroupCodeLogic.pendingKey), 'IOS123');
      expect(prefs.getBool(PendingGroupCodeLogic.iosCheckedKey), isTrue);
      expect(cleared, 1);
    });

    test('iOS: REMDY- grava; texto solto não grava e não limpa', () async {
      SharedPreferences.setMockInitialValues({
        PendingGroupCodeLogic.firstLaunchKey:
            freshInstall.millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      var cleared = 0;
      await InstallGroupAttribution.captureIfNeeded(
        isAndroid: false,
        isIos: true,
        readAndroidReferrer: () async => const AndroidReferrerRead(),
        readClipboard: () async => 'minha senha',
        clearClipboard: () async {
          cleared++;
        },
        clock: () => freshInstall,
        preferences: prefs,
      );
      expect(prefs.getString(PendingGroupCodeLogic.pendingKey), isNull);
      expect(cleared, 0);
      expect(prefs.getBool(PendingGroupCodeLogic.iosCheckedKey), isTrue);

      SharedPreferences.setMockInitialValues({
        PendingGroupCodeLogic.firstLaunchKey:
            freshInstall.millisecondsSinceEpoch,
      });
      final again = await SharedPreferences.getInstance();
      await InstallGroupAttribution.captureIfNeeded(
        isAndroid: false,
        isIos: true,
        readAndroidReferrer: () async => const AndroidReferrerRead(),
        readClipboard: () async => 'REMDY-pre999',
        clearClipboard: () async {
          cleared++;
        },
        clock: () => freshInstall,
        preferences: again,
      );
      expect(again.getString(PendingGroupCodeLogic.pendingKey), 'PRE999');
      expect(cleared, 1);
    });

    test('iOS: atualização não lê a área de transferência', () async {
      final old = freshInstall.subtract(const Duration(days: 3));
      SharedPreferences.setMockInitialValues({
        PendingGroupCodeLogic.firstLaunchKey: old.millisecondsSinceEpoch,
        'remember_me': true,
      });
      final prefs = await SharedPreferences.getInstance();
      var reads = 0;
      await InstallGroupAttribution.captureIfNeeded(
        isAndroid: false,
        isIos: true,
        readAndroidReferrer: () async => const AndroidReferrerRead(),
        readClipboard: () async {
          reads++;
          return 'https://remdy.app/g/ABC123';
        },
        clearClipboard: () async {},
        clock: () => freshInstall,
        preferences: prefs,
      );
      expect(reads, 0);
      expect(prefs.getString(PendingGroupCodeLogic.pendingKey), isNull);
      expect(prefs.getBool(PendingGroupCodeLogic.iosCheckedKey), isTrue);
    });

    test('iOS: segunda abertura não lê de novo', () async {
      SharedPreferences.setMockInitialValues({
        PendingGroupCodeLogic.firstLaunchKey:
            freshInstall.millisecondsSinceEpoch,
        PendingGroupCodeLogic.iosCheckedKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      var reads = 0;
      await InstallGroupAttribution.captureIfNeeded(
        isAndroid: false,
        isIos: true,
        readAndroidReferrer: () async => const AndroidReferrerRead(),
        readClipboard: () async {
          reads++;
          return 'REMDY-ABC123';
        },
        clearClipboard: () async {},
        clock: () => freshInstall,
        preferences: prefs,
      );
      expect(reads, 0);
    });
  });

  group('PendingGroupCodeStore', () {
    test('release só com a prévia montada e o mesmo código', () async {
      SharedPreferences.setMockInitialValues({
        PendingGroupCodeLogic.pendingKey: 'ABC123',
      });
      await PendingGroupCodeStore.releaseIfMatches(
        'ABC123',
        pageStillMounted: false,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PendingGroupCodeLogic.pendingKey), 'ABC123');

      await PendingGroupCodeStore.releaseIfMatches(
        'OTHER1',
        pageStillMounted: true,
      );
      expect(prefs.getString(PendingGroupCodeLogic.pendingKey), 'ABC123');

      await PendingGroupCodeStore.releaseIfMatches(
        'abc123',
        pageStillMounted: true,
      );
      expect(prefs.getString(PendingGroupCodeLogic.pendingKey), isNull);
    });
  });

  group('cadastro não apaga o código', () {
    test('telas de conta não removem pending_group_code', () {
      for (final path in [
        'lib/pages/login_page.dart',
        'lib/pages/age_verification_page.dart',
        'lib/pages/email_verification_page.dart',
        'lib/pages/edit_profile_page.dart',
        'lib/pages/splash_page.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src, isNot(contains("remove('pending_group_code')")),
            reason: path);
        expect(src, isNot(contains('releaseIfMatches')), reason: path);
      }
    });

    test('AuthGate segura até o portão e a prévia solta a chave', () {
      final auth = File('lib/pages/auth_gate.dart').readAsStringSync();
      final join = File('lib/pages/join_group_page.dart').readAsStringSync();
      expect(auth, contains('mayOpenPendingGroup'));
      expect(auth, contains('_applyPendingGroupIfAny(user)'));
      expect(auth, isNot(contains('releaseIfMatches')));
      expect(join, contains('addPostFrameCallback'));
      expect(join, contains('releaseIfMatches'));
      expect(
        auth.indexOf('AgeVerification.isVerified'),
        lessThan(auth.indexOf('_applyPendingGroupIfAny(user)')),
      );
    });

    test('campo manual está no cadastro e na busca, nos 5 idiomas', () {
      final login = File('lib/pages/login_page.dart').readAsStringSync();
      final groups = File('lib/pages/groups_list_page.dart').readAsStringSync();
      expect(login, contains("t.get('have_invite_code')"));
      expect(login, contains('have_invite_code_saved'));
      expect(groups, contains("t.get('have_invite_code')"));
      expect(groups, contains('JoinGroupPage'));

      const keys = [
        'have_invite_code',
        'have_invite_code_hint',
        'have_invite_code_invalid',
        'have_invite_code_saved',
      ];
      for (final code in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
        final json = File('lib/l10n/$code.json').readAsStringSync();
        for (final key in keys) {
          expect(json, contains('"$key"'), reason: '$code $key');
        }
      }
    });
  });

  test('AndroidManifest aceita o https resolvido do intent://', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final block = RegExp(
      r'<intent-filter[\s\S]*?android:pathPrefix="/g/"[\s\S]*?</intent-filter>',
    ).firstMatch(manifest);
    expect(block, isNotNull);
    final text = block!.group(0)!;
    expect(text, contains('android.intent.action.VIEW'));
    expect(text, contains('android:scheme="https"'));
    expect(text, contains('android:host="remdy.app"'));
    expect(text, contains('android:host="www.remdy.app"'));
  });

  test('Info.plist declara o esquema remdy', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<string>remdy</string>'));
  });

  test('primeiro uso usa a mesma chave do review prompt', () {
    expect(
      PendingGroupCodeLogic.firstLaunchKey,
      AppReviewPrompt.kFirstLaunch,
    );
  });

  test('build do app é 40 ou maior', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*\d+\.\d+\.\d+\+(\d+)', multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull);
    expect(int.parse(match!.group(1)!), greaterThanOrEqualTo(40));
  });
}
