import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:socialchat_mvp/services/group_creation_service.dart';
import 'package:socialchat_mvp/services/group_settings_service.dart';
import 'package:socialchat_mvp/widgets/group_bio_field.dart';
import 'package:socialchat_mvp/services/group_cover_upload.dart';
import 'package:socialchat_mvp/services/group_create_flow.dart';

void main() {
  group('GroupCoverUpload.contentTypeFromBytes', () {
    test('png pelos bytes, mesmo com extensão .jpg', () {
      final png =
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(GroupCoverUpload.contentTypeFromBytes(png), 'image/png');
    });
    test('webp', () {
      final webp = Uint8List.fromList(
          [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);
      expect(GroupCoverUpload.contentTypeFromBytes(webp), 'image/webp');
    });
    test('jpeg e desconhecido viram image/jpeg', () {
      expect(
          GroupCoverUpload.contentTypeFromBytes(
              Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
          'image/jpeg');
      expect(GroupCoverUpload.contentTypeFromBytes(Uint8List(0)), 'image/jpeg');
    });
  });

  test('códigos de erro do Storage viram mensagens específicas', () {
    expect(GroupCoverUpload.errorKeyForCode('unauthorized'),
        'group_cover_error_unauthorized');
    expect(GroupCoverUpload.errorKeyForCode('quota-exceeded'),
        'group_cover_error_too_large');
    expect(GroupCoverUpload.errorKeyForCode('unknown'),
        'group_cover_error_generic');
    expect(GroupCoverUpload.errorKeyForCode(null), 'group_cover_error_generic');
  });

  group('GroupCreateFlow.textErrorKey', () {
    test('nome acima de 80 usa a mensagem certa', () {
      expect(GroupCreateFlow.textErrorKey(name: 'a' * 81, bio: ''),
          'group_create_name_too_long');
      expect(GroupCreateFlow.textErrorKey(name: 'a' * 80, bio: ''), isNull);
    });
    test('bio até 3000', () {
      expect(
          GroupCreateFlow.textErrorKey(name: 'Grupo', bio: 'b' * 3000), isNull);
      expect(GroupCreateFlow.textErrorKey(name: 'Grupo', bio: 'b' * 3001),
          'group_create_bio_too_long');
    });
  });

  test('criar e editar mapeiam erro de bio para o texto do limite', () {
    final error = FirebaseFunctionsException(
        code: 'invalid-argument', message: 'Bio too long.');
    expect(GroupCreationService.errorKey(error), 'group_create_bio_too_long');
    expect(GroupSettingsService.errorKey(error), 'group_create_bio_too_long');
  });

  test('textos novos existem nas 5 línguas', () {
    const keys = [
      'group_create_name_too_long',
      'group_create_bio_too_long',
      'group_cover_error_unauthorized',
      'group_cover_error_too_large',
      'group_cover_error_generic',
    ];
    for (final loc in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final map = jsonDecode(File('lib/l10n/$loc.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(map['group_create_bio_too_long'], contains('3000'));
      for (final k in keys) {
        expect((map[k] ?? '').toString().trim(), isNotEmpty,
            reason: '$loc sem $k');
      }
    }
  });

  test('Functions usam o mesmo validador de bio 3000', () {
    final src = File('functions/index.js').readAsStringSync();
    final logic = File('functions/group_bio_logic.js').readAsStringSync();
    expect(logic, contains('GROUP_BIO_MAX_LENGTH = 3000'));
    expect(src, contains('value = validatedGroupBio(value)'));
    expect(src, contains('const bio = validatedGroupBio(dataIn.bio)'));
  });

  test('validador UTF-16: 2900 com emoji, 3000 e 3001', () {
    final seed = List.filled(80, '🎉👨‍👩‍👧 acentuação ção').join();
    for (final length in [2900, 3000, 3001]) {
      final bio = seed.padRight(length, 'a');
      expect(bio.length, length);
      expect(GroupCreateFlow.textErrorKey(name: 'Grupo', bio: bio),
          length <= 3000 ? null : 'group_create_bio_too_long');
    }
  });

  testWidgets('campo compartilhado de criar/editar conta emoji em UTF-16',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GroupBioField(
      controller: controller,
      decoration: const InputDecoration(),
    ))));
    final seed = List.filled(80, '🎉👨‍👩‍👧 acentuação ção').join();
    for (final length in [2900, 3000]) {
      await tester.enterText(
          find.byType(TextField), seed.padRight(length, 'a'));
      await tester.pump();
      expect(controller.text.length, length);
      expect(find.text('$length/3000'), findsOneWidget);
    }
    final accepted = controller.value;
    await tester.enterText(find.byType(TextField), seed.padRight(3001, 'a'));
    await tester.pump();
    expect(controller.value, accepted);
    expect(find.text('3000/3000'), findsOneWidget);
  });
}
