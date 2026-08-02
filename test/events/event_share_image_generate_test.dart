import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/models/event_presentation.dart';
import 'package:socialchat_mvp/services/event_share_image_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate social share png fixture', () async {
    final event = EventPresentation.fromMap('qa_share', {
      'title': 'Expo Remdy QA',
      'city': 'Toronto',
      'stateName': 'ON',
      'countryCode': 'ca',
      'startAt': DateTime(2026, 8, 15, 20, 0),
      'isActive': true,
      'status': 'approved',
      'coverUrl': '',
    });

    final bytes = await EventShareImageService.generateSocialPng(
      event: event,
      languageCode: 'pt',
    );
    expect(bytes.length, greaterThan(1000));

    final out = File(
      'tmp_part8/ios_qa/events_v1_profile_20260730_205358/screenshots/11_social_share_generated.png',
    );
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes, flush: true);
    // ignore: avoid_print
    print('WROTE ${out.path} bytes=${bytes.length}');
  });
}
