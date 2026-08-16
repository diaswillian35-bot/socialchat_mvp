import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Client for the `forwardMessage` callable (server validates all ACL).
class ForwardMessageService {
  ForwardMessageService._();
  static final ForwardMessageService instance = ForwardMessageService._();

  static const int maxDestinations = 5;

  bool _busy = false;
  bool get isBusy => _busy;

  Future<ForwardMessageResult> forward({
    required ForwardSource source,
    required List<ForwardDestination> destinations,
    required String intentId,
  }) async {
    if (_busy) {
      return ForwardMessageResult.busy();
    }
    if (destinations.isEmpty || destinations.length > maxDestinations) {
      return ForwardMessageResult.invalid();
    }
    _busy = true;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('forwardMessage');
      final result = await callable.call(<String, dynamic>{
        'intentId': intentId,
        'source': source.toMap(),
        'destinations': destinations.map((d) => d.toMap()).toList(),
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final rawResults =
          (data['results'] is List) ? data['results'] as List : [];
      final items = rawResults.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return ForwardDestinationResult(
          kind: '${m['kind'] ?? ''}',
          destinationId: '${m['destinationId'] ?? ''}',
          ok: m['ok'] == true,
          error: m['error']?.toString(),
          messageId: m['messageId']?.toString(),
        );
      }).toList();
      return ForwardMessageResult(
        ok: data['ok'] == true,
        duplicate: data['duplicate'] == true,
        successCount: (data['successCount'] is num)
            ? (data['successCount'] as num).toInt()
            : items.where((e) => e.ok).length,
        failureCount: (data['failureCount'] is num)
            ? (data['failureCount'] as num).toInt()
            : items.where((e) => !e.ok).length,
        results: items,
      );
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('ForwardMessage CF error: ${e.code} ${e.message}');
      }
      return ForwardMessageResult.failed(e.code);
    } catch (e) {
      if (kDebugMode) debugPrint('ForwardMessage error: $e');
      return ForwardMessageResult.failed('unknown');
    } finally {
      _busy = false;
    }
  }
}

class ForwardSource {
  const ForwardSource.dm({
    required this.conversationId,
    required this.messageId,
  })  : kind = 'dm',
        groupId = null;

  const ForwardSource.group({
    required this.groupId,
    required this.messageId,
  })  : kind = 'group',
        conversationId = null;

  final String kind;
  final String? conversationId;
  final String? groupId;
  final String messageId;

  Map<String, dynamic> toMap() => {
        'kind': kind,
        'messageId': messageId,
        if (conversationId != null) 'conversationId': conversationId,
        if (groupId != null) 'groupId': groupId,
      };
}

class ForwardDestination {
  const ForwardDestination.dm({
    this.conversationId,
    this.otherUid,
  })  : kind = 'dm',
        groupId = null;

  const ForwardDestination.group({required this.groupId})
      : kind = 'group',
        conversationId = null,
        otherUid = null;

  final String kind;
  final String? conversationId;
  final String? otherUid;
  final String? groupId;

  String get selectionKey {
    if (kind == 'group') return 'group:$groupId';
    if (conversationId != null && conversationId!.isNotEmpty) {
      return 'dm:$conversationId';
    }
    return 'dm_uid:$otherUid';
  }

  Map<String, dynamic> toMap() => {
        'kind': kind,
        if (conversationId != null) 'conversationId': conversationId,
        if (otherUid != null) 'otherUid': otherUid,
        if (groupId != null) 'groupId': groupId,
      };
}

class ForwardDestinationResult {
  ForwardDestinationResult({
    required this.kind,
    required this.destinationId,
    required this.ok,
    this.error,
    this.messageId,
  });

  final String kind;
  final String destinationId;
  final bool ok;
  final String? error;
  final String? messageId;
}

class ForwardMessageResult {
  ForwardMessageResult({
    required this.ok,
    required this.duplicate,
    required this.successCount,
    required this.failureCount,
    required this.results,
    this.errorCode,
  });

  factory ForwardMessageResult.busy() => ForwardMessageResult(
        ok: false,
        duplicate: false,
        successCount: 0,
        failureCount: 0,
        results: const [],
        errorCode: 'busy',
      );

  factory ForwardMessageResult.invalid() => ForwardMessageResult(
        ok: false,
        duplicate: false,
        successCount: 0,
        failureCount: 0,
        results: const [],
        errorCode: 'invalid',
      );

  factory ForwardMessageResult.failed(String code) => ForwardMessageResult(
        ok: false,
        duplicate: false,
        successCount: 0,
        failureCount: 0,
        results: const [],
        errorCode: code,
      );

  final bool ok;
  final bool duplicate;
  final int successCount;
  final int failureCount;
  final List<ForwardDestinationResult> results;
  final String? errorCode;
}
