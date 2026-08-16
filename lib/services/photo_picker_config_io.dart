import 'dart:io';

import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

bool configurePhotoPicker({
  ImagePickerPlatform? pickerPlatform,
  bool? isAndroid,
}) {
  if (!(isAndroid ?? Platform.isAndroid)) {
    return false;
  }

  final implementation = pickerPlatform ?? ImagePickerPlatform.instance;
  if (implementation is! ImagePickerAndroid) {
    return false;
  }

  implementation.useAndroidPhotoPicker = true;
  return true;
}
