import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'event_comments_logic.dart';

/// Curtidas de evento: `events/{eventId}/likes/{uid}` + `likesCount` agregado.
///
/// Contrato callable `toggleEventLike` (set semântico, sem coleção de requests):
/// `{ eventId, desiredLiked: bool }`
///
/// Custo típico da transação:
/// - reads: event + likes/{uid} (+ user);
/// - writes: 0 se já no estado; senão no máx. 1 like + 1 likesCount.
/// Sem listener da coleção `likes` — apenas 1 `get` pontual do doc do usuário.
class EventLikesService {
  EventLikesService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static DocumentReference<Map<String, dynamic>> likeRef({
    required FirebaseFirestore db,
    required String eventId,
    required String uid,
  }) {
    return db.collection('events').doc(eventId).collection('likes').doc(uid);
  }

  /// Uma leitura pontual — sem stream por usuário.
  static Future<bool> hasLiked({required String eventId}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final snap = await likeRef(
      db: FirebaseFirestore.instance,
      eventId: eventId,
      uid: uid,
    ).get();
    return snap.exists;
  }

  /// Define o estado desejado (idempotente). Retorna `{ liked, likesCount, changed? }`.
  static Future<Map<String, dynamic>> setLiked({
    required String eventId,
    required bool desiredLiked,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Login required.',
      );
    }

    final callable = _functions.httpsCallable('toggleEventLike');
    final result = await callable.call(<String, dynamic>{
      'eventId': eventId,
      'desiredLiked': desiredLiked,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Compat: preferir [setLiked] com estado explícito.
  static Future<Map<String, dynamic>> toggleLike({
    required String eventId,
    required bool desiredLiked,
  }) {
    return setLiked(eventId: eventId, desiredLiked: desiredLiked);
  }

  static String errorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'event_detail_login_required';
      case 'invalid-argument':
        return 'event_like_error';
      case 'failed-precondition':
        final msg = (e.message ?? '').toLowerCase();
        if (msg.contains('cancelled') || msg.contains('canceled')) {
          return 'event_cancelled';
        }
        return 'event_like_unavailable';
      case 'not-found':
      case 'unimplemented':
        return 'event_like_unavailable';
      default:
        return 'event_like_error';
    }
  }

  static bool eventAllowsLike(Map<String, dynamic> data) {
    final deleted = data['deleted'] == true;
    final active = data['isActive'] == true;
    final status = (data['status'] ?? '').toString().toLowerCase();
    final cancelled = status == 'cancelled' || status == 'canceled';
    final approved = status == 'approved';
    return EventCommentsLogic.canToggleLike(
      isAuthenticated: true,
      eventDeleted: deleted,
      eventCancelled: cancelled || !approved,
      eventActive: active,
    );
  }

  static int asInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }
}
