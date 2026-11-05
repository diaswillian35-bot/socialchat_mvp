import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/group_cover_upload.dart';
import 'package:socialchat_mvp/services/group_create_flow.dart';

void main() {
  group('GroupCoverUpload.contentTypeFromBytes', () {
    test('png pelos bytes, mesmo com extensão .jpg', () {
      final png = Uint8List.fromList(
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
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
      expect(GroupCoverUpload.contentTypeFromBytes(Uint8List(0)),
          'image/jpeg');
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
    test('bio até 2000', () {
      expect(GroupCreateFlow.textErrorKey(name: 'Grupo', bio: 'b' * 2000),
          isNull);
      expect(GroupCreateFlow.textErrorKey(name: 'Grupo', bio: 'b' * 2001),
          'group_create_bio_too_long');
    });
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
      for (final k in keys) {
        expect((map[k] ?? '').toString().trim(), isNotEmpty,
            reason: '$loc sem $k');
      }
    }
  });

  test('Functions usam o limite de bio 2000', () {
    final src = File('functions/index.js').readAsStringSync();
    expect(src.contains('bio.length > 1000'), isFalse);
    expect('bio.length > 2000'.allMatches(src).length, 2);
  });
}
