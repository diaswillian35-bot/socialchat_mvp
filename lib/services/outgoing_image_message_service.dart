import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../l10n/app_texts.dart';
import 'block_service.dart';
import 'group_ban_service.dart';
import 'group_discovery_logic.dart';
import 'international_chat_service.dart';
import 'outgoing_text_message_service.dart';
import 'premium_access_service.dart';

/// Envio de imagem (DM e grupo) a partir do job da Share Extension.
class OutgoingImageMessageService {
  OutgoingImageMessageService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  Future<OutgoingTextSendResult> send({
    required OutgoingTextSendTarget target,
    required String targetId,
    required String localPath,
    String otherUid = '',
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return OutgoingTextSendResult.fail('share_in_login_needed');
    }
    final file = File(localPath);
    if (!await file.exists() || await file.length() <= 0) {
      return OutgoingTextSendResult.fail('share_in_invalid');
    }
    if (target == OutgoingTextSendTarget.conversation) {
      return _sendDm(
        uid: uid,
        conversationId: targetId.trim(),
        otherUid: otherUid.trim(),
        file: file,
      );
    }
    return _sendGroup(uid: uid, groupId: targetId.trim(), file: file);
  }

  Future<OutgoingTextSendResult> _sendDm({
    required String uid,
    required String conversationId,
    required String otherUid,
    required File file,
  }) async {
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
    final canClient = InternationalChatService.canSendMessage(
      senderData: myData,
      recipientData: otherSnap.data() ?? {},
    );
    if (!canClient) {
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

    try {
      final fileName =
          'remdy_share_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage
          .ref()
          .child('chat_images')
          .child(conversationId)
          .child(fileName);
      await ref.putFile(
        file,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'fromUid': uid,
            'toUid': otherUid,
            'conversationId': conversationId,
          },
        ),
      );
      final imageUrl = await ref.getDownloadURL();
      final msgs = _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages');
      final pendingId = msgs.doc().id;
      await msgs.doc(pendingId).set({
        'type': 'image',
        'imageUrl': imageUrl,
        'senderId': uid,
        'fromUid': uid,
        'toUid': otherUid,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.fromDate(DateTime.now()),
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
        'hiddenFor': <String>[],
        'replyToMessageId': null,
        'replyToText': '',
        'replyToType': 'image',
        'replyToIsMe': false,
        'replyToImageUrl': '',
      });
      try {
        String label = '📷';
        try {
          label = AppTexts.current.get('chat_photo_label');
        } catch (_) {}
        await _db.collection('conversations').doc(conversationId).set(
          {
            'lastMessage': label,
            'lastMessageAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'unread.$otherUid': FieldValue.increment(1),
            'unread.$uid': 0,
          },
          SetOptions(merge: true),
        );
      } catch (e, st) {
        if (kDebugMode) debugPrint('ShareIn image DM summary: $e\n$st');
      }
      return OutgoingTextSendResult.success(pendingId);
    } catch (e, st) {
      if (kDebugMode) debugPrint('ShareIn image DM: $e\n$st');
      return OutgoingTextSendResult.fail('share_in_failed');
    }
  }

  Future<OutgoingTextSendResult> _sendGroup({
    required String uid,
    required String groupId,
    required File file,
  }) async {
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
    final groupCountry = (groupData['countryCode'] ?? groupData['country'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final isWorld = myCountry.isNotEmpty &&
        groupCountry.isNotEmpty &&
        myCountry != groupCountry;
    if (isWorld && !PremiumAccessService.isPremiumActiveFromData(myData)) {
      return OutgoingTextSendResult.fail('share_in_no_permission');
    }

    try {
      final fileName =
          'img_${DateTime.now().millisecondsSinceEpoch}_$uid.jpg';
      final ref = _storage
          .ref()
          .child('groups')
          .child(groupId)
          .child('images')
          .child(uid)
          .child(fileName);
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final imageUrl = await ref.getDownloadURL();
      final msgs = _db.collection('groups').doc(groupId).collection('messages');
      final pendingId = msgs.doc().id;
      final batch = _db.batch();
      batch.set(msgs.doc(pendingId), {
        'id': pendingId,
        'type': 'image',
        'text': '',
        'imageUrl': imageUrl,
        'senderId': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'replyToMessageId': null,
        'replyToText': '',
        'replyToType': 'image',
        'replyToIsMe': false,
        'replyToImageUrl': '',
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
      });
      batch.set(
        _db.collection('groups').doc(groupId).collection('reads').doc(uid),
        {
          'uid': uid,
          'lastReadAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
      return OutgoingTextSendResult.success(pendingId);
    } catch (e, st) {
      if (kDebugMode) debugPrint('ShareIn image group: $e\n$st');
      return OutgoingTextSendResult.fail('share_in_failed');
    }
  }
}
