import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/widgets/chat_composer_text.dart';

void main() {
  group('ChatComposerText.hasSendableText', () {
    test('1 empty → microfone (false)', () {
      expect(ChatComposerText.hasSendableText(''), isFalse);
    });

    test('2 first letter → Enviar (true)', () {
      expect(ChatComposerText.hasSendableText('a'), isTrue);
    });

    test('3 only spaces → microfone (false)', () {
      expect(ChatComposerText.hasSendableText('   '), isFalse);
      expect(ChatComposerText.hasSendableText('\n\t '), isFalse);
    });

    test('4 clear after text → microfone', () {
      expect(ChatComposerText.hasSendableText('oi'), isTrue);
      expect(ChatComposerText.hasSendableText(''), isFalse);
    });

    test('5 multiline → Enviar', () {
      expect(ChatComposerText.hasSendableText('linha1\nlinha2'), isTrue);
    });

    test('6 after send/clear → microfone', () {
      expect(ChatComposerText.hasSendableText('mensagem'), isTrue);
      expect(ChatComposerText.hasSendableText(''), isFalse);
    });
  });

  testWidgets('ListenableBuilder rebuilds mic/send from controller',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final send = ChatComposerText.hasSendableText(controller.text);
              return Icon(
                send ? Icons.send_rounded : Icons.mic_rounded,
                key: ValueKey(send ? 'send' : 'mic'),
              );
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('mic')), findsOneWidget);

    controller.text = 'x';
    await tester.pump();
    expect(find.byKey(const ValueKey('send')), findsOneWidget);

    controller.text = '   ';
    await tester.pump();
    expect(find.byKey(const ValueKey('mic')), findsOneWidget);

    controller.text = 'a\nb';
    await tester.pump();
    expect(find.byKey(const ValueKey('send')), findsOneWidget);

    controller.clear();
    await tester.pump();
    expect(find.byKey(const ValueKey('mic')), findsOneWidget);
  });

  test('DM and group pages derive visibility from controller (no dual state)',
      () {
    final dm = File('lib/pages/chat_page.dart').readAsStringSync();
    final group = File('lib/pages/group_chat_page.dart').readAsStringSync();

    expect(dm.contains('ListenableBuilder('), isTrue);
    expect(dm.contains('listenable: _textC'), isTrue);
    expect(dm.contains('ChatComposerText.hasSendableText'), isTrue);
    expect(dm.contains('bool _hasText'), isFalse);

    expect(group.contains('ListenableBuilder('), isTrue);
    expect(group.contains('listenable: _textC'), isTrue);
    expect(group.contains('ChatComposerText.hasSendableText'), isTrue);
  });

  test('duplicate send guarded by _sending in DM', () {
    final dm = File('lib/pages/chat_page.dart').readAsStringSync();
    expect(dm.contains('if (_sending) return;'), isTrue);
    expect(dm.contains('_sending = true;'), isTrue);
  });

  test('attachments (+) and audio (RecordingButton) preserved', () {
    final dm = File('lib/pages/chat_page.dart').readAsStringSync();
    final group = File('lib/pages/group_chat_page.dart').readAsStringSync();
    for (final src in [dm, group]) {
      expect(src.contains('_openPlusMenu'), isTrue);
      expect(src.contains('RecordingButton('), isTrue);
      expect(
        src.contains('Icons.add') || src.contains('Icons.add_rounded'),
        isTrue,
      );
    }
  });
}
