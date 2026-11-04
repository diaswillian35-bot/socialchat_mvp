import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Capa de grupo: escolha comprimida, tipo real da imagem e erro real.
class GroupCoverUpload {
  GroupCoverUpload._();

  static const int maxDimension = 1600;
  static const int quality = 80;

  /// Abre a galeria já comprimindo (JPEG ~80, lado maior <= 1600 px).
  static Future<XFile?> pick([ImagePicker? picker]) {
    return (picker ?? ImagePicker()).pickImage(
      source: ImageSource.gallery,
      imageQuality: quality,
      maxWidth: maxDimension.toDouble(),
      maxHeight: maxDimension.toDouble(),
    );
  }

  /// Tipo real pelos bytes iniciais (não pela extensão). Padrão: image/jpeg.
  static String contentTypeFromBytes(Uint8List head) {
    if (head.length >= 8 &&
        head[0] == 0x89 &&
        head[1] == 0x50 &&
        head[2] == 0x4E &&
        head[3] == 0x47) {
      return 'image/png';
    }
    if (head.length >= 12 &&
        head[0] == 0x52 &&
        head[1] == 0x49 &&
        head[2] == 0x46 &&
        head[3] == 0x46 &&
        head[8] == 0x57 &&
        head[9] == 0x45 &&
        head[10] == 0x42 &&
        head[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  static String extensionFor(String contentType) {
    switch (contentType) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      default:
        return 'jpg';
    }
  }

  /// Chave de texto (AppTexts) para um código de erro do Firebase Storage.
  static String errorKeyForCode(String? code) {
    switch (code) {
      case 'unauthorized':
      case 'unauthenticated':
      case 'permission-denied':
        return 'group_cover_error_unauthorized';
      case 'quota-exceeded':
      case 'object-too-large':
        return 'group_cover_error_too_large';
      default:
        return 'group_cover_error_generic';
    }
  }

  /// Chave de texto para qualquer erro do upload, com log do erro real.
  static String errorKeyFor(Object error, [StackTrace? stack]) {
    if (error is FirebaseException) {
      debugPrint(
        '[GroupCover] upload falhou: plugin=${error.plugin} '
        'code=${error.code} message=${error.message}',
      );
      return errorKeyForCode(error.code);
    }
    debugPrint('[GroupCover] upload falhou: $error');
    if (stack != null) debugPrint(stack.toString());
    return 'group_cover_error_generic';
  }

  /// Envia a capa e devolve a URL e o caminho no Storage.
  /// Lança o erro original (FirebaseException etc.) para o chamador tratar.
  static Future<GroupCoverResult> upload({
    required String groupId,
    required String uid,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    final head = bytes.length > 16 ? bytes.sublist(0, 16) : bytes;
    final contentType = contentTypeFromBytes(head);
    final ref = FirebaseStorage.instance
        .ref()
        .child('groups')
        .child(groupId)
        .child('avatar')
        .child('group_avatar_$uid.${extensionFor(contentType)}');
    await ref.putFile(
      File(file.path),
      SettableMetadata(contentType: contentType),
    );
    final url = await ref.getDownloadURL();
    return GroupCoverResult(url: url, path: ref.fullPath);
  }
}

class GroupCoverResult {
  const GroupCoverResult({required this.url, required this.path});
  final String url;
  final String path;
}
