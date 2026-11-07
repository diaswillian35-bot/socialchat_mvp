import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/widgets/group_invite_share_button.dart';

void main() {
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final calls = <MethodCall>[];
  const buttonKey = ValueKey('group-share');

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'dev.fluttercommunity.plus/share/dismissed';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget button(
      {String link = 'https://remdy.app/g/FRE8B5', VoidCallback? onError}) {
    return MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.topRight,
      child: GroupInviteShareButton(
        key: buttonKey,
        inviteLink: link,
        onError: onError ?? () {},
        child: const Text('Compartilhar'),
      ),
    )));
  }

  testWidgets('shares exact public invite with a non-empty button origin',
      (tester) async {
    var errors = 0;
    await tester.pumpWidget(button(onError: () => errors++));
    final rect = tester.getRect(find.byKey(buttonKey));
    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'share');
    final args = calls.single.arguments as Map;
    expect(args['text'], 'https://remdy.app/g/FRE8B5');
    expect(args['originX'], rect.left);
    expect(args['originY'], rect.top);
    expect(args['originWidth'], rect.width);
    expect(args['originHeight'], rect.height);
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
    expect(errors, 0); // User cancelling is not an error.
  });

  testWidgets('empty invite stays disabled without generating or writing codes',
      (tester) async {
    await tester.pumpWidget(button(link: ''));
    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets('native platform exception reaches existing error snackbar hook',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'error', message: 'sharePositionOrigin');
    });
    var errors = 0;
    await tester.pumpWidget(button(onError: () => errors++));
    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();
    expect(errors, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late native error does not notify a disposed group page',
      (tester) async {
    final pending = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      pending.add(call);
      await Future<void>.delayed(const Duration(seconds: 1));
      throw PlatformException(code: 'error');
    });
    var errors = 0;
    await tester.pumpWidget(button(onError: () => errors++));
    await tester.tap(find.text('Compartilhar'));
    await tester.pump();
    expect(pending, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(errors, 0);
    expect(tester.takeException(), isNull);
  });

  test('group page wires the tested button to the five-language error', () {
    final page = File('lib/pages/group_info_page.dart').readAsStringSync();
    expect(page, contains('GroupInviteShareButton('));
    expect(page, contains("_toast(AppTexts.t('group_share_error'))"));
    expect(page, contains('https://remdy.app/g/\$code'));
    expect(page, isNot(contains('await Share.share(inviteLink)')));
    for (final locale in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final catalog =
          jsonDecode(File('lib/l10n/$locale.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(catalog['group_share_error'], isA<String>());
      expect((catalog['group_share_error'] as String).isNotEmpty, isTrue);
    }
  });
}
