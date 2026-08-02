import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'event_comments_logic.dart';

/// Comentários de eventos via Cloud Functions.
class EventCommentsService {
  EventCommentsService._();

  static const int maxCommentLength = EventCommentsLogic.maxCommentLength;

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static String newRequestId() {
    final ms = DateTime.now().microsecondsSinceEpoch;
    final r = Random().nextInt(1 << 32);
    return 'c_${ms}_$r';
  }

  /// Pré-aloca ID estável (mesma bolha pending → confirmado).
  static String allocateCommentId({required String eventId}) {
    return FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .collection('comments')
        .doc()
        .id;
  }

  static Future<Map<String, dynamic>> createComment({
    required String eventId,
    required String text,
    required String requestId,
    required String commentId,
    String? replyToCommentId,
    DateTime? clientCreatedAt,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Login required.',
      );
    }

    final callable = _functions.httpsCallable('createEventComment');
    final payload = <String, dynamic>{
      'eventId': eventId,
      'text': text,
      'requestId': requestId,
      'commentId': commentId,
      'clientCreatedAtMs':
          (clientCreatedAt ?? DateTime.now()).millisecondsSinceEpoch,
    };
    final replyId = (replyToCommentId ?? '').trim();
    if (replyId.isNotEmpty) {
      payload['replyToCommentId'] = replyId;
    }
    final result = await callable.call(payload);
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<Map<String, dynamic>> toggleLike({
    required String eventId,
    required String commentId,
  }) async {
    final callable = _functions.httpsCallable('toggleEventCommentLike');
    final result = await callable.call(<String, dynamic>{
      'eventId': eventId,
      'commentId': commentId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<Map<String, dynamic>> deleteComment({
    required String eventId,
    required String commentId,
  }) async {
    final callable = _functions.httpsCallable('deleteEventComment');
    final result = await callable.call(<String, dynamic>{
      'eventId': eventId,
      'commentId': commentId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  static String createErrorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'event_detail_login_required';
      case 'invalid-argument':
        final msg = (e.message ?? '').toLowerCase();
        if (msg.contains('empty')) return 'event_comment_empty';
        if (msg.contains('too long')) return 'event_comment_too_long';
        return 'event_comment_publish_error';
      case 'failed-precondition':
        final msg = (e.message ?? '').toLowerCase();
        if (msg.contains('cancelled') || msg.contains('canceled')) {
          return 'event_cancelled';
        }
        if (msg.contains('deleted') || msg.contains('available')) {
          return 'event_comment_unavailable';
        }
        return 'event_comment_publish_error';
      case 'not-found':
        return 'event_comment_unavailable';
      default:
        return 'event_comment_publish_error';
    }
  }

  static String likeErrorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'event_detail_login_required';
      case 'failed-precondition':
      case 'not-found':
        return 'event_comment_unavailable';
      default:
        return 'event_comment_like_error';
    }
  }

  static String deleteErrorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'event_comment_delete_error';
      case 'not-found':
        return 'event_comment_unavailable';
      default:
        return 'event_comment_delete_error';
    }
  }

  static int asInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  static List<String> asUidList(dynamic value) {
    if (value is! List) return const <String>[];
    return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
}

/// Comentário local (pending / failed) fundido com snapshot remoto.
class PendingEventComment {
  PendingEventComment({
    required this.commentId,
    required this.requestId,
    required this.text,
    required this.clientCreatedAt,
    this.replyToCommentId,
    this.replyToName,
    this.replyToText,
    this.rootCommentId,
    this.status = PendingEventCommentStatus.sending,
  });

  final String commentId;
  final String requestId;
  final String text;
  final DateTime clientCreatedAt;
  final String? replyToCommentId;
  final String? replyToName;
  final String? replyToText;
  final String? rootCommentId;
  PendingEventCommentStatus status;
}

enum PendingEventCommentStatus { sending, failed }
