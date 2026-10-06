import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/widgets/chat_composer_text.dart';
import 'package:socialchat_mvp/widgets/remdy_keyboard_caps.dart';

void main() {
  test('composer keyboard hint stays sentence case', () {
    expect(
      ChatComposerText.keyboardCapitalization,
      RemdyKeyboardCaps.sentences,
    );
    expect(
      ChatComposerText.keyboardCapitalization,
      TextCapitalization.sentences,
    );
  });

  test('every TextField/TextFormField in lib sets textCapitalization', () {
    final lib = Directory('lib');
    final missing = <String>[];
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final src = file.readAsStringSync();
      var i = 0;
      while (true) {
        final tf = src.indexOf('TextField(', i);
        final tff = src.indexOf('TextFormField(', i);
        var at = -1;
        var keywordLen = 0;
        if (tf >= 0 && (tff < 0 || tf < tff)) {
          at = tf;
          keywordLen = 'TextField('.length;
        } else if (tff >= 0) {
          at = tff;
          keywordLen = 'TextFormField('.length;
        }
        if (at < 0) break;
        final end = _matchingParen(src, at + keywordLen - 1);
        if (end < 0) {
          missing.add('${file.path}: unclosed field at $at');
          break;
        }
        final block = src.substring(at, end + 1);
        if (!block.contains('textCapitalization:')) {
          missing.add('${file.path}:\n$block');
        }
        i = end + 1;
      }
    }
    expect(missing, isEmpty, reason: missing.join('\n---\n'));
  });

  test('narrative fields keep sentences; sensitive fields keep none', () {
    expect(
      _fieldCaps('lib/pages/chat_page.dart', '_textC'),
      contains('ChatComposerText'),
    );
    expect(
      _fieldCaps('lib/pages/group_chat_page.dart', '_textC'),
      contains('ChatComposerText'),
    );
    expect(
      _fieldCaps('lib/pages/event_detail_page.dart', '_commentC'),
      contains('RemdyKeyboardCaps.sentences'),
    );
    expect(
      _fieldCaps('lib/pages/event_detail_page.dart', '_replyC'),
      contains('RemdyKeyboardCaps.sentences'),
    );
    expect(
      _fieldCaps('lib/pages/profile_page.dart', '_aboutC'),
      contains('RemdyKeyboardCaps.sentences'),
    );
    expect(
      _fieldCaps('lib/pages/edit_profile_page.dart', '_aboutC'),
      contains('RemdyKeyboardCaps.sentences'),
    );
    expect(
      _fieldCaps('lib/pages/create_group_page.dart', '_bioC'),
      contains('RemdyKeyboardCaps.sentences'),
    );
    expect(
      _fieldCaps(
        'lib/widgets/events/event_editorial_wizard.dart',
        '_descC',
      ),
      contains('RemdyKeyboardCaps.sentences'),
    );
    expect(
      _fieldCaps('lib/pages/support_contact_page.dart', '_messageC'),
      contains('RemdyKeyboardCaps.sentences'),
    );
    expect(
      _fieldCaps('lib/pages/share_in_page.dart', '_textC'),
      contains('RemdyKeyboardCaps.sentences'),
    );
    expect(
      _fieldCaps('lib/pages/remi_chat_page.dart', '_messageC'),
      contains('RemdyKeyboardCaps.sentences'),
    );
    expect(
      _fieldCaps('lib/services/post_uploader.dart', '_captionC'),
      contains('RemdyKeyboardCaps.sentences'),
    );
    expect(
      _fieldCaps('lib/pages/group_info_page.dart', 'reasonC'),
      contains('RemdyKeyboardCaps.sentences'),
    );

    expect(
      _fieldCaps('lib/pages/profile_page.dart', '_nameC'),
      contains('RemdyKeyboardCaps.words'),
    );
    expect(
      _fieldCaps('lib/pages/edit_profile_page.dart', '_nameC'),
      contains('RemdyKeyboardCaps.words'),
    );
    expect(
      _fieldCaps('lib/pages/create_group_page.dart', '_nameC'),
      contains('RemdyKeyboardCaps.words'),
    );
    expect(
      _fieldCaps(
        'lib/widgets/events/event_editorial_wizard.dart',
        '_titleC',
      ),
      contains('RemdyKeyboardCaps.words'),
    );

    expect(
      _fieldCaps('lib/pages/login_page.dart', '_emailC'),
      contains('RemdyKeyboardCaps.none'),
    );
    expect(
      _fieldCaps('lib/pages/login_page.dart', '_passC'),
      contains('RemdyKeyboardCaps.none'),
    );
    expect(
      _fieldCaps('lib/pages/login_page.dart', '_confirmC'),
      contains('RemdyKeyboardCaps.none'),
    );
    expect(
      _fieldCaps('lib/pages/forgot_password_page.dart', '_emailC'),
      contains('RemdyKeyboardCaps.none'),
    );
    expect(
      _fieldCaps('lib/pages/delete_account_page.dart', '_passwordCtrl'),
      contains('RemdyKeyboardCaps.none'),
    );
    expect(
      _fieldCaps('lib/pages/support_contact_page.dart', '_emailC'),
      contains('RemdyKeyboardCaps.none'),
    );
    expect(
      _fieldCaps('lib/pages/support_contact_page.dart', '_phoneC'),
      contains('RemdyKeyboardCaps.none'),
    );
    expect(
      _fieldCaps('lib/pages/user_search_page.dart', '_controller'),
      contains('RemdyKeyboardCaps.none'),
    );
    expect(
      _fieldCaps(
        'lib/widgets/events/event_editorial_wizard.dart',
        '_ticketUrlC',
      ),
      contains('RemdyKeyboardCaps.none'),
    );
    expect(
      _fieldCaps(
        'lib/widgets/events/event_editorial_wizard.dart',
        '_websiteC',
      ),
      contains('RemdyKeyboardCaps.none'),
    );
  });

  test('delete-account confirm word stays characters, not sentences', () {
    expect(
      _fieldCaps('lib/pages/delete_account_page.dart', '_confirmCtrl'),
      contains('TextCapitalization.characters'),
    );
  });
}

String _fieldCaps(String path, String controllerName) {
  final src = File(path).readAsStringSync();
  final needle = 'controller: $controllerName';
  final at = src.indexOf(needle);
  expect(at, isNonNegative, reason: '$path missing $needle');
  final start = src.lastIndexOf(RegExp(r'Text(Form)?Field\('), at);
  expect(start, isNonNegative, reason: '$path no TextField before $needle');
  final open = src.indexOf('(', start);
  final end = _matchingParen(src, open);
  return src.substring(start, end + 1);
}

int _matchingParen(String src, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < src.length; i++) {
    final c = src[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}
