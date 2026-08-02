import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'block_service.dart';
import 'group_ban_service.dart';
import 'group_discovery_logic.dart';
import 'international_chat_service.dart';
import 'link_preview_service.dart';
import 'premium_access_service.dart';

enum OutgoingTextSendTarget { conversation, group }

class OutgoingTextSendRequest {
  const OutgoingTextSendRequest({
    required this.target,
    required this.targetId,
    required this.text,
    this.otherUid = '',
    this.messageId,
  });

  final OutgoingTextSendTarget target;
  final String targetId;
  final String text;
  final String otherUid;

  /// ID pré-alocado para retry sem duplicar.
  final String? messageId;
}

class OutgoingTextSendResult {
  const OutgoingTextSendResult({
    required this.ok,
    this.messageId,
    this.errorKey,
  });

  factory OutgoingTextSendResult.success(String messageId) =>
      OutgoingTextSendResult(ok: true, messageId: messageId);

  factory OutgoingTextSendResult.fail(String errorKey) =>
      OutgoingTextSendResult(ok: false, errorKey: errorKey);

  final bool ok;
  final String? messageId;
  final String? errorKey;
}

/// Envio estável de texto/link (DM e grupo) — mesmo contrato do chat.
class OutgoingTextMessageService {
  OutgoingTextMessageService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static final Set<String> _inFlightIds = <String>{};

  /// Testes.
  @visibleForTesting
  static void resetInFlightForTest() => _inFlightIds.clear();

  Future<OutgoingTextSendResult> send(OutgoingTextSendRequest request) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return OutgoingTextSendResult.fail('share_in_login_needed');
    }

    final text = request.text.trim();
    if (text.isEmpty) {
      return OutgoingTextSendResult.fail('share_in_invalid');
    }
    if (_containsPhone(text)) {
      return OutgoingTextSendResult.fail('chat_phone_not_allowed');
    }

    if (request.target == OutgoingTextSendTarget.conversation) {
      return _sendDm(uid: uid, request: request, text: text);
    }
    return _sendGroup(uid: uid, request: request, text: text);
  }

  Future<OutgoingTextSendResult> _sendDm({
    required String uid,
    required OutgoingTextSendRequest request,
    required String text,
  }) async {
    final conversationId = request.targetId.trim();
    final otherUid = request.otherUid.trim();
    if (conversationId.isEmpty || otherUid.isEmpty) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }

    final mySnap = await _db.collection('users').doc(uid).get();
    final myData = mySnap.data() ?? {};
    if (myData['shadowBan'] == true) {
      return OutgoingTextSendResult.fail('user_temporarily_silenced');
    }
    if (myData['isBanned'] == true) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }

    if (await BlockService.isEitherBlocked(otherUid)) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }

    final otherSnap = await _db.collection('users').doc(otherUid).get();
    if (!InternationalChatService.canSendMessage(
      senderData: myData,
      recipientData: otherSnap.data() ?? {},
    )) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }

    final convSnap =
        await _db.collection('conversations').doc(conversationId).get();
    if (!convSnap.exists) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }
    final participants = (convSnap.data()?['participants'] is List)
        ? List<String>.from(
            (convSnap.data()!['participants'] as List).map((e) => '$e'),
          )
        : <String>[];
    if (!participants.contains(uid) || !participants.contains(otherUid)) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }

    final msgs = _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages');
    final pendingId = (request.messageId?.trim().isNotEmpty == true)
        ? request.messageId!.trim()
        : msgs.doc().id;

    if (!_begin(pendingId)) {
      return OutgoingTextSendResult.fail('share_in_sending');
    }

    try {
      final clientNow = Timestamp.fromDate(DateTime.now());
      await msgs.doc(pendingId).set({
        'type': 'text',
        'text': text,
        'senderId': uid,
        'fromUid': uid,
        'toUid': otherUid,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': clientNow,
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
        'replyToMessageId': null,
        'replyToText': '',
        'replyToType': 'text',
        'replyToIsMe': false,
        'replyToImageUrl': '',
      });

      unawaited(
        LinkPreviewService.requestPreviewForMessage(
          text: text,
          messagePath: 'conversations/$conversationId/messages/$pendingId',
        ),
      );

      try {
        await _updateConversationSummary(
          conversationId: conversationId,
          myUid: uid,
          otherUid: otherUid,
          lastMessage: text,
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('ShareIn DM summary: $e\n$st');
        }
      }

      return OutgoingTextSendResult.success(pendingId);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ShareIn DM send: $e\n$st');
      }
      return OutgoingTextSendResult.fail('share_in_failed');
    } finally {
      _end(pendingId);
    }
  }

  Future<OutgoingTextSendResult> _sendGroup({
    required String uid,
    required OutgoingTextSendRequest request,
    required String text,
  }) async {
    final groupId = request.targetId.trim();
    if (groupId.isEmpty) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }

    final mySnap = await _db.collection('users').doc(uid).get();
    final myData = mySnap.data() ?? {};
    if (myData['shadowBan'] == true) {
      return OutgoingTextSendResult.fail('user_temporarily_silenced');
    }
    if (myData['isBanned'] == true) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }

    final groupSnap = await _db.collection('groups').doc(groupId).get();
    if (!groupSnap.exists) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }
    final groupData = groupSnap.data() ?? {};
    if (GroupDiscoveryLogic.isDeletedOrInactive(groupData)) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }
    if (!GroupDiscoveryLogic.isParticipating(data: groupData, uid: uid)) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }
    if (await GroupBanService.isUserBanned(groupId: groupId, uid: uid)) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }

    final myCountry = InternationalChatService.readHomeCountryCode(myData);
    final groupCountry =
        (groupData['countryCode'] ?? groupData['country'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final isWorld = myCountry.isNotEmpty &&
        groupCountry.isNotEmpty &&
        myCountry != groupCountry;
    final isPremium = PremiumAccessService.isPremiumActiveFromData(myData);
    if (isWorld && !isPremium) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }

    final msgs = _db.collection('groups').doc(groupId).collection('messages');
    final pendingId = (request.messageId?.trim().isNotEmpty == true)
        ? request.messageId!.trim()
        : msgs.doc().id;

    if (!_begin(pendingId)) {
      return OutgoingTextSendResult.fail('share_in_sending');
    }

    try {
      final batch = _db.batch();
      final msgRef = msgs.doc(pendingId);
      // Do not write clientCreatedAt: group messageCreateKeysOk() reject it.
      batch.set(msgRef, {
        'id': pendingId,
        'type': 'text',
        'text': text,
        'senderId': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'replyToMessageId': null,
        'replyToText': '',
        'replyToType': 'text',
        'replyToIsMe': false,
        'replyToImageUrl': '',
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
      });

      final readRef = _db.collection('groups').doc(groupId).collection('reads').doc(uid);
      batch.set(
        readRef,
        {
          'uid': uid,
          'lastReadAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      unawaited(
        LinkPreviewService.requestPreviewForMessage(
          text: text,
          messagePath: 'groups/$groupId/messages/$pendingId',
        ),
      );

      return OutgoingTextSendResult.success(pendingId);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ShareIn group send: $e\n$st');
      }
      return OutgoingTextSendResult.fail('share_in_failed');
    } finally {
      _end(pendingId);
    }
  }

  Future<void> _updateConversationSummary({
    required String conversationId,
    required String myUid,
    required String otherUid,
    required String lastMessage,
  }) async {
    final convDoc = _db.collection('conversations').doc(conversationId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(convDoc);
      final data = snap.data() ?? {};
      final unread = Map<String, dynamic>.from(
        (data['unread'] is Map) ? data['unread'] as Map : {},
      );
      final otherCount =
          (unread[otherUid] is int) ? unread[otherUid] as int : 0;
      unread[otherUid] = otherCount + 1;
      unread[myUid] = 0;
      tx.set(
        convDoc,
        {
          'lastMessage': lastMessage,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'unread': unread,
        },
        SetOptions(merge: true),
      );
    });
  }

  bool _begin(String id) {
    if (_inFlightIds.contains(id)) return false;
    _inFlightIds.add(id);
    return true;
  }

  void _end(String id) => _inFlightIds.remove(id);

  bool _containsPhone(String text) {
    final t = text.trim();
    final intl = RegExp(r'\+\s?\d{1,3}');
    final generic = RegExp(r'\d[\d\s().-]{7,}\d');
    return intl.hasMatch(t) || generic.hasMatch(t);
  }
}
