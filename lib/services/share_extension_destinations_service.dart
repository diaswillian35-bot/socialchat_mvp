import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'age_access_service.dart';
import 'group_discovery_logic.dart';
import 'international_chat_service.dart';

/// Writes the logged-in user's chats/groups into the App Group for the
/// iOS Share Extension (no tokens). Used when share callables are unavailable.
class ShareExtensionDestinationsService {
  ShareExtensionDestinationsService._();

  static const MethodChannel _channel = MethodChannel('remdy/share_session');
  static bool _busy = false;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> publish() async {
    if (!_supported) return;
    if (_busy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (!await AgeAccessService.currentUserIsVerified()) return;

    _busy = true;
    try {
      final db = FirebaseFirestore.instance;
      final mySnap = await db.collection('users').doc(uid).get();
      final myData = mySnap.data() ?? {};

      // Keep Share Extension payload light (memory + App Group JSON).
      const maxItems = 30;
      final convSnap = await db
          .collection('conversations')
          .where('participants', arrayContains: uid)
          .limit(maxItems)
          .get();

      final dms = <Map<String, dynamic>>[];
      for (final doc in convSnap.docs) {
        final data = doc.data();
        final hidden = (data['hiddenFor'] is List)
            ? List<String>.from((data['hiddenFor'] as List).map((e) => '$e'))
            : <String>[];
        if (hidden.contains(uid)) continue;
        final parts = (data['participants'] is List)
            ? List<String>.from((data['participants'] as List).map((e) => '$e'))
            : <String>[];
        final otherUid = parts.firstWhere((u) => u != uid, orElse: () => '');
        if (otherUid.isEmpty) continue;

        String name = '';
        try {
          final other = await db.collection('users').doc(otherUid).get();
          final u = other.data() ?? {};
          name = (u['name'] ?? u['displayName'] ?? '').toString().trim();
        } catch (_) {}
        if (name.isEmpty) name = 'Remdy';

        var allowed = true;
        try {
          final otherData =
              await InternationalChatService.fetchUserData(otherUid) ?? {};
          allowed = InternationalChatService.canSendMessage(
            senderData: myData,
            recipientData: otherData,
          );
        } catch (_) {}

        final last = data['lastMessageAt'] ?? data['updatedAt'];
        dms.add({
          'destinationId': doc.id,
          'type': 'dm',
          'otherUid': otherUid,
          'displayName': name,
          // Initials-only UI in the extension — skip remote photo URLs.
          'photoUrl': '',
          'location': '',
          'allowed': allowed,
          'blockedReason': allowed ? '' : 'blocked',
          'online': false,
          'memberCount': 0,
          'lastMessageAtMs': _tsMs(last),
        });
      }
      dms.sort(
        (a, b) => (_asInt(b['lastMessageAtMs'])).compareTo(_asInt(a['lastMessageAtMs'])),
      );
      if (dms.length > maxItems) {
        dms.removeRange(maxItems, dms.length);
      }

      QuerySnapshot<Map<String, dynamic>> groupSnap;
      try {
        groupSnap = await db
            .collection('groups')
            .where('members', arrayContains: uid)
            .limit(maxItems)
            .get();
      } catch (_) {
        groupSnap = await db
            .collection('groups')
            .where('ownerId', isEqualTo: uid)
            .limit(maxItems)
            .get();
      }

      final groups = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final doc in groupSnap.docs) {
        if (!seen.add(doc.id)) continue;
        final data = doc.data();
        if (GroupDiscoveryLogic.isDeletedOrInactive(data)) continue;
        if (!GroupDiscoveryLogic.isParticipating(data: data, uid: uid)) {
          continue;
        }
        final title =
            (data['name'] ?? data['title'] ?? 'Grupo').toString().trim();
        groups.add({
          'destinationId': doc.id,
          'type': 'group',
          'otherUid': '',
          'displayName': title.isEmpty ? 'Grupo' : title,
          'photoUrl': '',
          'location': '',
          'allowed': true,
          'blockedReason': '',
          'online': false,
          'memberCount': _memberCount(data),
          'lastMessageAtMs': _tsMs(data['lastMessageAt'] ?? data['updatedAt']),
        });
      }
      if (groups.length > maxItems) {
        groups.removeRange(maxItems, groups.length);
      }

      await _channel.invokeMethod<dynamic>('saveDestinations', {
        'conversations': dms,
        'groups': groups,
      });
      debugPrint(
        'ShareExtDestinations: published dms=${dms.length} groups=${groups.length}',
      );
    } catch (e) {
      debugPrint('ShareExtDestinations publish failed: ${e.runtimeType}');
    } finally {
      _busy = false;
    }
  }

  static int _memberCount(Map<String, dynamic> data) {
    final members = data['members'];
    if (members is List) return members.length;
    final n = data['membersCount'] ?? data['memberCount'];
    if (n is int) return n;
    if (n is num) return n.toInt();
    return 0;
  }

  static int _tsMs(dynamic raw) {
    if (raw is Timestamp) return raw.millisecondsSinceEpoch;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}
