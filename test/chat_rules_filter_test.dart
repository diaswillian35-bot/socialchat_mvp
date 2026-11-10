import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/chat_rules_filter.dart';
import 'package:socialchat_mvp/services/chat_rules_lists.g.dart';

/// b44: o filtro do app tem de decidir igual ao servidor.
void main() {
  final cases = (jsonDecode(File('functions/moderation/parity_cases.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  test('paridade app x servidor (insultos, palavrão, links, telefones)', () {
    expect(cases.length, greaterThan(150));
    expect(cases.where((c) => c['insultsOnly'] == 'insult').length, greaterThanOrEqualTo(100));
    expect(
      cases.where((c) => c['insultsOnly'] == null && c['loose'] == null).length,
      greaterThanOrEqualTo(200),
    );
    for (final c in cases) {
      final text = c['text'] as String;
      expect(ChatRulesFilter.profanity(text), c['insultsOnly'], reason: 'insultos: $text');
      expect(ChatRulesFilter.profanity(text, loose: true), c['loose'], reason: 'loose: $text');
      expect(ChatRulesFilter.evaluateGroup(text, const {}), c['groupDefault'], reason: 'grupo padrão: $text');
      expect(
          ChatRulesFilter.evaluateGroup(text, const {
            'modBot': {'blockProfanity': true}
          }),
          c['groupStrict'],
          reason: 'grupo com palavrão: $text');
    }
  });

  test('lista gerada igual à fonte (word_lists.json)', () {
    final src = File('lib/services/chat_rules_lists.g.dart').readAsStringSync();
    expect(src, contains('GERADO'));
    expect(chatRulesInsults, isNotEmpty);
    expect(chatRulesLoose, isNotEmpty);
  });

  test('config do bot: padrão recomendado e por grupo', () {
    expect(ChatRulesFilter.botFlag(null, 'welcomeEnabled'), isTrue);
    expect(ChatRulesFilter.botFlag(null, 'blockLinks'), isTrue);
    expect(ChatRulesFilter.botFlag(null, 'blockPhones'), isTrue);
    expect(ChatRulesFilter.botFlag(null, 'blockProfanity'), isFalse);
    expect(
        ChatRulesFilter.evaluateGroup('www.site.com', const {
          'modBot': {'blockLinks': false}
        }),
        isNull);
    expect(ChatRulesFilter.noticeKey('bot_phone'), 'bot_blocked_phone');
  });
}
