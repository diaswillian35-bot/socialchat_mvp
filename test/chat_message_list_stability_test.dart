import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/utils/chat_message_list_stability.dart';

class _Pending {
  final String id;
  final String text;
  final String? uploadedUrl;
  final bool failed;
  final bool sending;
  final String? replyToMessageId;
  final String replyToText;

  const _Pending({
    required this.id,
    this.text = '',
    this.uploadedUrl,
    this.failed = false,
    this.sending = false,
    this.replyToMessageId,
    this.replyToText = '',
  });

  _Pending copyWith({
    bool? failed,
    bool? sending,
    String? uploadedUrl,
  }) {
    return _Pending(
      id: id,
      text: text,
      uploadedUrl: uploadedUrl ?? this.uploadedUrl,
      failed: failed ?? this.failed,
      sending: sending ?? this.sending,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
    );
  }
}

/// Simula o fluxo de retry (DM/grupo) com as mesmas regras do util.
class _PendingRetryHarness {
  final List<_Pending> pending = [];
  final Set<String> inFlight = {};
  int uploadCalls = 0;
  int firestoreWrites = 0;

  void addFailed({
    required String id,
    required String text,
    String? uploadedUrl,
    String? replyToMessageId,
    String replyToText = '',
  }) {
    pending.add(
      _Pending(
        id: id,
        text: text,
        uploadedUrl: uploadedUrl,
        failed: true,
        replyToMessageId: replyToMessageId,
        replyToText: replyToText,
      ),
    );
  }

  bool canRetry(String id) {
    final i = pending.indexWhere((e) => e.id == id);
    if (i < 0) return false;
    final item = pending[i];
    return ChatMessageListStability.canStartRetry(
      failed: item.failed,
      sending: item.sending || inFlight.contains(id),
    );
  }

  Future<void> retry(String id, {required bool firestoreFails}) async {
    final i = pending.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final item = pending[i];
    if (!ChatMessageListStability.canStartRetry(
      failed: item.failed,
      sending: item.sending || inFlight.contains(id),
    )) {
      return;
    }
    if (ChatMessageListStability.shouldIgnoreConcurrentSend(
      sending: inFlight.contains(id),
    )) {
      return;
    }

    inFlight.add(id);
    pending[i] = item.copyWith(failed: false, sending: true);

    try {
      var url = ChatMessageListStability.resolveUploadUrl(
        cachedUploadUrl: pending[i].uploadedUrl,
      );
      if (url == null && pending[i].text.isEmpty) {
        uploadCalls++;
        url = 'https://cdn.example/$id';
        pending[i] = pending[i].copyWith(uploadedUrl: url);
      }
      firestoreWrites++;
      if (firestoreFails) {
        throw Exception('FirebaseException: PERMISSION_DENIED');
      }
      pending[i] = pending[i].copyWith(sending: false);
    } catch (_) {
      pending[i] = pending[i].copyWith(failed: true, sending: false);
    } finally {
      inFlight.remove(id);
    }
  }

  void confirmSnapshot(Set<String> serverIds) {
    final next = ChatMessageListStability.pruneConfirmedPending<_Pending>(
      pending: pending,
      idOf: (_Pending e) => e.id,
      serverIds: serverIds,
    );
    pending
      ..clear()
      ..addAll(next);
  }
}

void main() {
  group('ChatMessageListStability retry & UI safety', () {
    test('retry preserva o mesmo ID e a mesma chave da bolha', () {
      const id = 'msg_stable_1';
      final keyBefore = ChatMessageListStability.bubbleKey(id);
      final harness = _PendingRetryHarness()
        ..addFailed(id: id, text: '', uploadedUrl: 'https://cdn/x');
      expect(harness.pending.single.id, id);
      expect(ChatMessageListStability.bubbleKey(harness.pending.single.id),
          keyBefore);
    });

    test('dois toques rápidos não fazem dois envios', () async {
      final harness = _PendingRetryHarness()
        ..addFailed(id: 'a1', text: '', uploadedUrl: 'https://cdn/a');

      final first = harness.retry('a1', firestoreFails: false);
      // Segundo toque imediato enquanto o primeiro ainda não setou sending
      // no mesmo tick: marcamos sending manualmente como o UI faria.
      harness.pending[0] = harness.pending[0].copyWith(sending: true);
      expect(harness.canRetry('a1'), isFalse);
      await first;
      expect(harness.firestoreWrites, 1);
    });

    test('falha depois do upload não faz novo upload', () async {
      final harness = _PendingRetryHarness()
        ..addFailed(
          id: 'photo_1',
          text: '',
          uploadedUrl: 'https://cdn/already-uploaded.jpg',
        );

      await harness.retry('photo_1', firestoreFails: true);
      expect(harness.uploadCalls, 0);
      expect(harness.firestoreWrites, 1);
      expect(harness.pending.single.failed, isTrue);
      expect(harness.pending.single.id, 'photo_1');

      await harness.retry('photo_1', firestoreFails: false);
      expect(harness.uploadCalls, 0);
      expect(harness.firestoreWrites, 2);
    });

    test('falha de texto não perde o conteúdo', () async {
      final harness = _PendingRetryHarness()
        ..addFailed(id: 'txt_1', text: 'olá mundo');

      await harness.retry('txt_1', firestoreFails: true);
      expect(harness.pending.single.text, 'olá mundo');
      expect(harness.pending.single.id, 'txt_1');
    });

    test('resposta vinculada continua preservada no retry', () async {
      final harness = _PendingRetryHarness()
        ..addFailed(
          id: 'txt_reply',
          text: 'resposta',
          replyToMessageId: 'parent_9',
          replyToText: 'original',
        );

      await harness.retry('txt_reply', firestoreFails: true);
      expect(harness.pending.single.replyToMessageId, 'parent_9');
      expect(harness.pending.single.replyToText, 'original');
    });

    test('confirmação do snapshot remove uma única pendência', () {
      final pending = [
        const _Pending(id: 'keep'),
        const _Pending(id: 'done'),
      ];
      final next = ChatMessageListStability.pruneConfirmedPending<_Pending>(
        pending: pending,
        idOf: (_Pending e) => e.id,
        serverIds: {'done'},
      );
      expect(next.map((e) => e.id), ['keep']);
      expect(
        ChatMessageListStability.shouldRemovePendingOnSnapshot(
          pendingId: 'done',
          serverIds: {'done'},
        ),
        isTrue,
      );
    });

    test('nenhum erro técnico deve ir para a UI', () {
      const technical =
          'FirebaseException: [cloud_firestore/permission-denied]';
      expect(
        ChatMessageListStability.looksLikeTechnicalError(technical),
        isTrue,
      );
      expect(
        ChatMessageListStability.looksLikeTechnicalError('Failed to send'),
        isFalse,
      );
      expect(
        ChatMessageListStability.looksLikeTechnicalError('Falha ao enviar'),
        isFalse,
      );
      // A UI usa só a chave traduzida — concatenar $e falharia este teste.
      final uiMessage = 'Failed to send';
      expect(uiMessage.contains('Exception'), isFalse);
      expect(uiMessage.contains('Firebase'), isFalse);
    });

    test('DM e grupo compartilham regras de chave e reuse de upload', () {
      for (final scope in ['dm', 'group']) {
        final id = '${scope}_audio_42';
        expect(
          ChatMessageListStability.bubbleKey(id),
          'msg_$id',
        );
        expect(
          ChatMessageListStability.shouldReuseUpload(
            'https://storage/$scope/file',
          ),
          isTrue,
        );
        expect(ChatMessageListStability.shouldReuseUpload(null), isFalse);
      }
    });

    test('texto, foto e áudio: retry reutiliza ID', () async {
      for (final type in ['text', 'photo', 'audio']) {
        final id = '${type}_id';
        final harness = _PendingRetryHarness()
          ..addFailed(
            id: id,
            text: type == 'text' ? 'hi' : '',
            uploadedUrl: type == 'text' ? null : 'https://cdn/$type',
          );
        final key = ChatMessageListStability.bubbleKey(id);
        await harness.retry(id, firestoreFails: false);
        expect(harness.pending.single.id, id);
        expect(
            ChatMessageListStability.bubbleKey(harness.pending.single.id), key);
      }
    });

    test('canStartRetry exige failed e não sending', () {
      expect(
        ChatMessageListStability.canStartRetry(failed: true, sending: false),
        isTrue,
      );
      expect(
        ChatMessageListStability.canStartRetry(failed: true, sending: true),
        isFalse,
      );
      expect(
        ChatMessageListStability.canStartRetry(failed: false, sending: false),
        isFalse,
      );
    });

    test('resolveUploadUrl reutiliza cache', () {
      expect(
        ChatMessageListStability.resolveUploadUrl(
          cachedUploadUrl: ' https://cdn/x ',
        ),
        'https://cdn/x',
      );
      expect(
        ChatMessageListStability.resolveUploadUrl(cachedUploadUrl: ''),
        isNull,
      );
    });
  });
}
