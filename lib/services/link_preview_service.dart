import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'message_link_utils.dart';

/// Cliente da callable `fetchLinkPreview`.
///
/// A falha da prévia NUNCA deve impedir o envio da mensagem.
/// O servidor grava metadados sanitizados no doc da mensagem (Admin SDK).
class LinkPreviewService {
  LinkPreviewService._();

  static final Set<String> _inFlight = <String>{};

  /// Dispara geração controlada após envio bem-sucedido.
  /// Não escuta permanentemente; uma chamada por mensagem/URL.
  static Future<void> requestPreviewForMessage({
    required String text,
    required String messagePath,
  }) async {
    final candidate = MessageLinkUtils.firstPreviewCandidate(text);
    if (candidate == null) return;
    if (candidate.isRemdyInternal) return;

    final key = '$messagePath|${candidate.normalizedHttpsUrl}';
    if (_inFlight.contains(key)) return;
    _inFlight.add(key);

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('fetchLinkPreview');
      await callable.call(<String, dynamic>{
        'url': candidate.normalizedHttpsUrl,
        'messagePath': messagePath,
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('LinkPreview: falha não bloqueante: $e\n$st');
      }
    } finally {
      _inFlight.remove(key);
    }
  }
}
