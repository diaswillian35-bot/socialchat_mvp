import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

/// Foto de perfil obrigatória (users.photoUrl / profilePhotoUrl).
class ProfilePhoto {
  ProfilePhoto._();

  static String urlFromData(Map<String, dynamic>? data) {
    for (final k in ['photoUrl', 'profilePhotoUrl', 'photoURL']) {
      final v = (data?[k] ?? '').toString().trim();
      if (v.startsWith('http')) return v;
    }
    return '';
  }

  static bool hasPhoto(Map<String, dynamic>? data) =>
      urlFromData(data).isNotEmpty;

  /// Perfil completo mas sem foto: volta para completar o perfil (vale para
  /// todos, inclusive o admin).
  static bool needsPhoto(Map<String, dynamic>? data) =>
      data != null && data['profileComplete'] == true && !hasPhoto(data);

  /// Mesmo fluxo do Menu > Perfil: galeria, qualidade 80,
  /// users/{uid}/profile/{uuid}.jpg. Null se cancelou.
  static Future<String?> pickAndUpload(String uid) async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return null;
    final ref = FirebaseStorage.instance
        .ref()
        .child('users/$uid/profile/${const Uuid().v4()}.jpg');
    final meta = SettableMetadata(contentType: 'image/jpeg');
    if (kIsWeb) {
      await ref.putData(await file.readAsBytes(), meta);
    } else {
      await ref.putFile(File(file.path), meta);
    }
    return ref.getDownloadURL();
  }
}
