import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Caminho único de imagens de eventos:
/// `events/{eventId}/photos/{fileName}`
class EventImageStorage {
  EventImageStorage._();

  static Reference photoRef({
    required String eventId,
    required String fileName,
  }) {
    return FirebaseStorage.instance
        .ref()
        .child('events')
        .child(eventId)
        .child('photos')
        .child(fileName);
  }

  /// Upload preferencial via bytes (mais confiável no iOS que [File] path).
  static Future<String> uploadJpegBytes({
    required String eventId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final path = 'events/$eventId/photos/$fileName';
    debugPrint('[CREATE EVENT] storage path: $path');
    debugPrint('[CREATE EVENT] upload bytes: ${bytes.length}');

    if (bytes.isEmpty) {
      throw StateError('empty_image_bytes');
    }

    final ref = photoRef(eventId: eventId, fileName: fileName);
    await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await ref.getDownloadURL();
    debugPrint('[CREATE EVENT] uploaded URL ok (${url.length} chars)');
    return url;
  }

  static Future<String> uploadJpegXFile({
    required String eventId,
    required XFile file,
    required String fileName,
  }) async {
    final bytes = await file.readAsBytes();
    return uploadJpegBytes(
      eventId: eventId,
      bytes: bytes,
      fileName: fileName,
    );
  }

  /// Mantido para chamadas legadas baseadas em path de arquivo.
  static Future<String> uploadJpeg({
    required String eventId,
    required dynamic file,
    required String fileName,
  }) async {
    if (file is XFile) {
      return uploadJpegXFile(
        eventId: eventId,
        file: file,
        fileName: fileName,
      );
    }
    final bytes = await (file as dynamic).readAsBytes() as Uint8List;
    return uploadJpegBytes(
      eventId: eventId,
      bytes: bytes,
      fileName: fileName,
    );
  }

  static Future<void> deleteByUrl(String url) async {
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (e) {
      debugPrint('[CREATE EVENT] deleteByUrl failed: $e');
    }
  }
}
