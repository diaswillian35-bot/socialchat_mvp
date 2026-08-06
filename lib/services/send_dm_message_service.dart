import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'dm_reply_quota.dart';

class SendDmMessageResult {
  const SendDmMessageResult({
    required this.ok,
    this.messageId,
    this.quota,
    this.errorCode,
    this.errorMessage,
    this.idempotentReplay = false,
  });

  final bool ok;
  final String? messageId;
  final DmReplyQuota? quota;
  final String? errorCode;
  final String? errorMessage;
  final bool idempotentReplay;

  bool get isQuotaExceeded =>
      errorCode == 'quota-exceeded' || errorCode == 'resource-exhausted';
}

/// Cliente da Callable [sendDmMessage] (franquia Free internacional).
class SendDmMessageService {
  SendDmMessageService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  Future<SendDmMessageResult> send({
    required String conversationId,
    required String otherUid,
    required String text,
    required String requestId,
    String? messageId,
    String? replyToMessageId,
    String? replyToText,
    String? replyToType,
    bool replyToIsMe = false,
  }) async {
    try {
      final callable = _functions.httpsCallable('sendDmMessage');
      final resp = await callable.call(<String, dynamic>{
        'conversationId': conversationId,
        'otherUid': otherUid,
        'text': text,
        'requestId': requestId,
        if (messageId != null && messageId.isNotEmpty) 'messageId': messageId,
        if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
        if (replyToText != null) 'replyToText': replyToText,
        if (replyToType != null) 'replyToType': replyToType,
        'replyToIsMe': replyToIsMe,
      });
      final data = Map<String, dynamic>.from(resp.data as Map? ?? {});
      final rqRaw = data['replyQuota'];
      DmReplyQuota? quota;
      if (rqRaw is Map) {
        quota = DmReplyQuota.fromMap(Map<String, dynamic>.from(rqRaw));
      }
      return SendDmMessageResult(
        ok: data['ok'] == true,
        messageId: (data['messageId'] ?? '').toString(),
        quota: quota,
        idempotentReplay: data['idempotentReplay'] == true,
      );
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('sendDmMessage CF error: ${e.code} ${e.message} ${e.details}');
      }
      String? detailCode;
      DmReplyQuota? quota;
      final details = e.details;
      if (details is Map) {
        detailCode = (details['code'] ?? '').toString();
        final rq = details['replyQuota'];
        if (rq is Map) {
          quota = DmReplyQuota.fromMap(Map<String, dynamic>.from(rq));
        }
      }
      final code = detailCode?.isNotEmpty == true
          ? detailCode!
          : (e.code == 'resource-exhausted' ? 'quota-exceeded' : e.code);
      return SendDmMessageResult(
        ok: false,
        errorCode: code,
        errorMessage: e.message,
        quota: quota,
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('sendDmMessage failed: $e\n$st');
      return const SendDmMessageResult(
        ok: false,
        errorCode: 'internal',
        errorMessage: 'Send failed',
      );
    }
  }
}
