import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/audio_rooms/audio_room_service.dart';

void main() {
  test('only owner, admin and moderator manage the room', () {
    expect(audioRoomIsModeratorRole('owner'), isTrue);
    expect(audioRoomIsModeratorRole('admin'), isTrue);
    expect(audioRoomIsModeratorRole('moderator'), isTrue);
    expect(audioRoomIsModeratorRole('member'), isFalse);
    expect(audioRoomIsModeratorRole('outsider'), isFalse);
  });

  test('server error codes map to UI text keys', () {
    expect(
        audioRoomErrorKey(FirebaseFunctionsException(
            code: 'resource-exhausted', message: 'room_full')),
        'audio_room_full');
    expect(
        audioRoomErrorKey(FirebaseFunctionsException(
            code: 'failed-precondition', message: 'no_live_room')),
        'audio_room_ended');
    expect(audioRoomErrorKey(Exception('x')), 'audio_room_error');
  });

  test('room doc parsing tolerates missing fields', () {
    final r = AudioRoomInfo.fromDoc('r1', {
      'openedBy': 'u1',
      'presentUids': ['a', '', 'b'],
    });
    expect(r.presentUids, ['a', 'b']);
    expect(r.speakerUids, isEmpty);
    expect(r.participantCount, 0);
  });

  test('audio room texts exist in all 5 languages', () {
    final langs = ['pt-BR', 'pt-PT', 'en', 'es', 'fr'];
    final maps = {
      for (final l in langs)
        l: jsonDecode(File('lib/l10n/$l.json').readAsStringSync())
            as Map<String, dynamic>
    };
    final keys =
        maps['pt-BR']!.keys.where((k) => k.startsWith('audio_room_')).toSet();
    expect(keys.length, greaterThanOrEqualTo(26));
    for (final l in langs) {
      for (final k in keys) {
        expect((maps[l]![k] ?? '').toString().trim(), isNotEmpty,
            reason: '$l missing $k');
      }
    }
  });
}
