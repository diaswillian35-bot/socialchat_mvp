import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/widgets/chat_composer_text.dart';

void main() {
  group('ChatComposerText.keyboardCapitalization', () {
    test('uses sentence capitalization for new phrases', () {
      expect(
        ChatComposerText.keyboardCapitalization,
        TextCapitalization.sentences,
      );
    });

    testWidgets('TextField applies sentence capitalization from composer',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              textCapitalization: ChatComposerText.keyboardCapitalization,
              inputFormatters: [
                ChatComposerText.leadingAlphaCapitalizationFormatter,
              ],
              keyboardType: TextInputType.multiline,
            ),
          ),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textCapitalization, TextCapitalization.sentences);
      expect(field.keyboardType, TextInputType.multiline);
      expect(field.inputFormatters, isNotNull);
      expect(
        field.inputFormatters!
            .contains(ChatComposerText.leadingAlphaCapitalizationFormatter),
        isTrue,
      );
    });
  });

  group('ChatComposerText.capitalizeLeadingAlpha', () {
    test('teste → Teste', () {
      expect(ChatComposerText.capitalizeLeadingAlpha('teste'), 'Teste');
    });

    test('leading spaces preserved', () {
      expect(ChatComposerText.capitalizeLeadingAlpha('  teste'), '  Teste');
    });

    test('emoji before first word', () {
      expect(ChatComposerText.capitalizeLeadingAlpha('😊 teste'), '😊 Teste');
    });

    test('accented first letter', () {
      expect(ChatComposerText.capitalizeLeadingAlpha('áudio'), 'Áudio');
    });

    test('empty stays empty', () {
      expect(ChatComposerText.capitalizeLeadingAlpha(''), '');
      expect(ChatComposerText.prepareOutgoingText('   '), '');
    });

    test('already capitalized unchanged', () {
      expect(ChatComposerText.capitalizeLeadingAlpha('Teste'), 'Teste');
    });

    test('multiline only first alpha', () {
      expect(
        ChatComposerText.capitalizeLeadingAlpha('olá\nmundo'),
        'Olá\nmundo',
      );
    });

    test('emoji-only unchanged', () {
      expect(ChatComposerText.capitalizeLeadingAlpha('😊🎉'), '😊🎉');
    });

    test('rest of text unchanged', () {
      expect(
        ChatComposerText.capitalizeLeadingAlpha('teste DE chat'),
        'Teste DE chat',
      );
    });

    test('https link at start not altered', () {
      const url = 'https://remdy.app/e/abc';
      expect(ChatComposerText.capitalizeLeadingAlpha(url), url);
    });

    test('www link at start not altered', () {
      const url = 'www.example.com/path';
      expect(ChatComposerText.capitalizeLeadingAlpha(url), url);
    });

    test('mention handle not altered', () {
      expect(ChatComposerText.capitalizeLeadingAlpha('@willian oi'), '@willian oi');
    });

    test('text before link capitalizes word only', () {
      expect(
        ChatComposerText.capitalizeLeadingAlpha('veja https://remdy.app'),
        'Veja https://remdy.app',
      );
    });

    test('prepareOutgoingText trims then capitalizes', () {
      expect(ChatComposerText.prepareOutgoingText('  teste  '), 'Teste');
      expect(ChatComposerText.prepareOutgoingText('😊 teste'), '😊 Teste');
    });
  });

  group('LeadingAlphaCapitalizationFormatter paste/type', () {
    test('formatter capitalizes pasted lowercase', () {
      final formatter = ChatComposerText.leadingAlphaCapitalizationFormatter;
      final next = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(
          text: 'teste colado',
          selection: TextSelection.collapsed(offset: 12),
        ),
      );
      expect(next.text, 'Teste colado');
      expect(next.selection.baseOffset, 12);
    });

    test('formatter preserves selection when casing changes', () {
      final formatter = ChatComposerText.leadingAlphaCapitalizationFormatter;
      final next = formatter.formatEditUpdate(
        const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        ),
        const TextEditingValue(
          text: 'a',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      expect(next.text, 'A');
      expect(next.selection.baseOffset, 1);
    });
  });

  test('message composers use sentence keyboard capitalization + formatter', () {
    final dm = File('lib/pages/chat_page.dart').readAsStringSync();
    final group = File('lib/pages/group_chat_page.dart').readAsStringSync();
    final shareIn = File('lib/pages/share_in_page.dart').readAsStringSync();

    for (final src in [dm, group, shareIn]) {
      expect(src.contains('textCapitalization:'), isTrue);
      expect(src.contains('.keyboardCapitalization'), isTrue);
      expect(src.contains('leadingAlphaCapitalizationFormatter'), isTrue);
      expect(src.contains('prepareOutgoingText'), isTrue);
      expect(
        RegExp(r'controller:\s*_textC[\s\S]{0,500}textCapitalization:')
            .hasMatch(src),
        isTrue,
      );
    }
  });

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
