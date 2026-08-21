import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'age_access_service.dart';
import 'outgoing_image_message_service.dart';
import 'outgoing_text_message_service.dart';

/// Consome jobs gravados pela Share Extension no App Group.
class ShareExtensionIncomingService {
  ShareExtensionIncomingService._();

  static const MethodChannel _channel = MethodChannel('remdy/share_session');
  static bool _busy = false;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> consumePendingJobs() async {
    if (!_supported) return;
    if (_busy) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    if (!await AgeAccessService.currentUserIsVerified()) return;

    try {
      final diag = await _channel.invokeMethod<String>('peekShareDiag');
      if (diag != null && diag.isNotEmpty) {
        debugPrint('ShareExtDiagHost: ${diag.length} chars');
      }
    } catch (_) {}

    _busy = true;
    try {
      final raw = await _channel.invokeMethod<dynamic>('peekShareJobs');
      if (raw is! List || raw.isEmpty) return;
      final sender = OutgoingImageMessageService();
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final jobId = '${map['jobId'] ?? map['intentId'] ?? ''}'.trim();
        if (jobId.isEmpty) continue;
        final destinationId = '${map['destinationId'] ?? ''}'.trim();
        final kind = '${map['kind'] ?? ''}'.trim().toLowerCase();
        final otherUid = '${map['otherUid'] ?? ''}'.trim();
        final text = '${map['text'] ?? ''}'.trim();
        final paths = (map['filePaths'] is List)
            ? List<String>.from(
                (map['filePaths'] as List).map((e) => '$e'),
              )
            : const <String>[];
        if (destinationId.isEmpty || (text.isEmpty && paths.isEmpty)) continue;

        var allOk = true;
        final target = kind == 'group'
            ? OutgoingTextSendTarget.group
            : OutgoingTextSendTarget.conversation;
        if (text.isNotEmpty) {
          final textResult = await OutgoingTextMessageService().send(
            OutgoingTextSendRequest(
              target: target,
              targetId: destinationId,
              text: text,
              otherUid: otherUid,
            ),
          );
          if (!textResult.ok) {
            allOk = false;
            debugPrint('ShareExt text job failed: ${textResult.errorKey}');
          }
        }
        for (final path in paths) {
          if (!File(path).existsSync()) {
            allOk = false;
            break;
          }
          final result = await sender.send(
            target: target,
            targetId: destinationId,
            localPath: path,
            otherUid: otherUid,
          );
          if (!result.ok) {
            allOk = false;
            debugPrint('ShareExt image job failed: ${result.errorKey}');
            break;
          }
        }
        if (allOk) {
          await _channel.invokeMethod<dynamic>('ackShareJob', {'jobId': jobId});
        }
      }
    } catch (e) {
      debugPrint('ShareExt consume jobs failed: ${e.runtimeType}');
    } finally {
      _busy = false;
    }
  }
}
