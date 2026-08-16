import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:socialchat_mvp/services/photo_picker_config_io.dart';

void main() {
  test('enables the Android Photo Picker', () {
    final picker = ImagePickerAndroid();

    expect(picker.useAndroidPhotoPicker, isFalse);
    expect(
      configurePhotoPicker(pickerPlatform: picker, isAndroid: true),
      isTrue,
    );
    expect(picker.useAndroidPhotoPicker, isTrue);
  });

  test('does not configure the Android implementation on other platforms', () {
    final picker = ImagePickerAndroid();

    expect(
      configurePhotoPicker(pickerPlatform: picker, isAndroid: false),
      isFalse,
    );
    expect(picker.useAndroidPhotoPicker, isFalse);
  });

  test('source manifest removes broad photo and storage permissions', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    for (final permission in <String>[
      'android.permission.READ_MEDIA_IMAGES',
      'android.permission.READ_MEDIA_VIDEO',
      'android.permission.READ_EXTERNAL_STORAGE',
    ]) {
      final removal = RegExp(
        '<uses-permission\\s+(?=[^>]*android:name="$permission")'
        '(?=[^>]*tools:node="remove")[^>]*/>',
        dotAll: true,
      );
      expect(removal.hasMatch(manifest), isTrue, reason: permission);
    }

    expect(manifest, contains('android.permission.CAMERA'));
    expect(manifest, contains('android.permission.RECORD_AUDIO'));
  });
}
