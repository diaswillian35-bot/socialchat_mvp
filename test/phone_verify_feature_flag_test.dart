import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/phone_verify_feature_flag.dart';
import 'package:socialchat_mvp/widgets/phone_verify_menu_gate.dart';

void main() {
  tearDown(PhoneVerifyFeatureFlag.resetDebugOverride);

  String source(String path) => File(path).readAsStringSync();

  test('flag compilada padrão é falsa e a chave é REMDY_PHONE_VERIFY_ENABLED',
      () {
    expect(PhoneVerifyFeatureFlag.defineKey, 'REMDY_PHONE_VERIFY_ENABLED');
    expect(PhoneVerifyFeatureFlag.compiledEnabled, isFalse);
    PhoneVerifyFeatureFlag.resetDebugOverride();
    expect(PhoneVerifyFeatureFlag.isEnabled, isFalse);
  });

  test('debugOverride liga e desliga; showMenuEntry mantém desvincular', () {
    PhoneVerifyFeatureFlag.debugOverride = false;
    expect(PhoneVerifyFeatureFlag.isEnabled, isFalse);
    expect(
      PhoneVerifyFeatureFlag.showMenuEntry(alreadyVerified: false),
      isFalse,
    );
    expect(
      PhoneVerifyFeatureFlag.showMenuEntry(alreadyVerified: true),
      isTrue,
    );

    PhoneVerifyFeatureFlag.debugOverride = true;
    expect(PhoneVerifyFeatureFlag.isEnabled, isTrue);
    expect(
      PhoneVerifyFeatureFlag.showMenuEntry(alreadyVerified: false),
      isTrue,
    );
    expect(
      PhoneVerifyFeatureFlag.showMenuEntry(alreadyVerified: true),
      isTrue,
    );
  });

  testWidgets('item some com flag off e aparece com flag on', (tester) async {
    const tile = Key('menu_verify_profile');

    Widget app({required bool alreadyVerified}) {
      return MaterialApp(
        home: Scaffold(
          body: PhoneVerifyMenuGate(
            alreadyVerified: alreadyVerified,
            child: const ListTile(
              key: tile,
              title: Text('Verificar meu perfil'),
            ),
          ),
        ),
      );
    }

    PhoneVerifyFeatureFlag.debugOverride = false;
    await tester.pumpWidget(app(alreadyVerified: false));
    expect(find.byKey(tile), findsNothing);
    expect(find.text('Verificar meu perfil'), findsNothing);

    PhoneVerifyFeatureFlag.debugOverride = true;
    await tester.pumpWidget(app(alreadyVerified: false));
    await tester.pump();
    expect(find.byKey(tile), findsOneWidget);
    expect(find.text('Verificar meu perfil'), findsOneWidget);

    PhoneVerifyFeatureFlag.debugOverride = false;
    await tester.pumpWidget(app(alreadyVerified: true));
    await tester.pump();
    expect(find.byKey(tile), findsOneWidget);
  });

  test(
      'menu e a tela de verificação respeitam a flag; chaves e página permanecem',
      () {
    final menu = source('lib/pages/menu_page.dart');
    final page = source('lib/pages/verify_phone_page.dart');
    expect(menu, contains('PhoneVerifyFeatureFlag.showMenuEntry'));
    expect(menu, contains('PhoneVerifyMenuGate'));
    expect(menu, contains('const VerifyPhonePage()'));
    expect(page, contains('PhoneVerifyFeatureFlag.isEnabled'));
    expect(page, contains('unlinkVerifiedPhone'));
    expect(File('lib/pages/verify_phone_page.dart').existsSync(), isTrue);

    for (final code in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final json = source('lib/l10n/$code.json');
      expect(json, contains('"verify_profile_title"'), reason: code);
      expect(json, contains('"verify_remove"'), reason: code);
    }
  });
}
