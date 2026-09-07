import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'group_pending_join_badge_logic.dart';

class GroupPendingJoinCounts {
  const GroupPendingJoinCounts({
    this.byGroupId = const {},
    this.total = 0,
  });

  final Map<String, int> byGroupId;
  final int total;

  int forGroup(String groupId) => byGroupId[groupId] ?? 0;
}

/// Badges de pedidos pendentes para owner/admin.
///
/// Reutiliza a query de membership (`members` arrayContains) já usada no shell.
/// Rules: collectionGroup só lê o próprio uid — listeners de `pendingRequests`
/// ficam só nos grupos admin+approval (subconjunto da membership).
class GroupPendingJoinBadgeService {
  GroupPendingJoinBadgeService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  static final GroupPendingJoinBadgeService instance =
      GroupPendingJoinBadgeService();

  final FirebaseFirestore _db;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _groupsSub;
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _pendingSubs = {};
  final Map<String, int> _counts = {};
  final StreamController<GroupPendingJoinCounts> _controller =
      StreamController<GroupPendingJoinCounts>.broadcast();

  String? _uid;
  bool _started = false;

  Stream<GroupPendingJoinCounts> get stream async* {
    yield GroupPendingJoinCounts(
      byGroupId: Map<String, int>.from(_counts),
      total: GroupPendingJoinBadgeLogic.sumGroupCounts(_counts),
    );
    yield* _controller.stream;
  }

  void ensureStarted() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      stop();
      return;
    }
    if (_started && _uid == uid) return;
    stop();
    _uid = uid;
    _started = true;

    _groupsSub = _db
        .collection('groups')
        .where('members', arrayContains: uid)
        .where('deleted', isEqualTo: false)
        .snapshots()
        .listen(
      (snap) {
        final watchIds = <String>{};
        for (final doc in snap.docs) {
          final data = doc.data();
          if (GroupPendingJoinBadgeLogic.watchesPendingForGroup(
            data: data,
            uid: uid,
          )) {
            watchIds.add(doc.id);
          }
        }
        _reconcilePendingWatchers(watchIds);
      },
      onError: (e, st) {
        debugPrint('GroupPendingJoinBadge groups stream: $e');
      },
    );
  }

  void stop() {
    _groupsSub?.cancel();
    _groupsSub = null;
    for (final s in _pendingSubs.values) {
      s.cancel();
    }
    _pendingSubs.clear();
    _counts.clear();
    _uid = null;
    _started = false;
    _emit();
  }

  void _reconcilePendingWatchers(Set<String> groupIds) {
    final removed =
        _pendingSubs.keys.where((id) => !groupIds.contains(id)).toList();
    for (final id in removed) {
      _pendingSubs.remove(id)?.cancel();
      _counts.remove(id);
    }

    for (final groupId in groupIds) {
      if (_pendingSubs.containsKey(groupId)) continue;
      _pendingSubs[groupId] = _db
          .collection('groups')
          .doc(groupId)
          .collection('pendingRequests')
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .listen(
        (snap) {
          final entries = snap.docs.map(
            (d) => MapEntry(d.id, d.data()),
          );
          _counts[groupId] =
              GroupPendingJoinBadgeLogic.countPendingDocs(entries);
          _emit();
        },
        onError: (e, st) {
          debugPrint('GroupPendingJoinBadge pending $groupId: $e');
          _counts[groupId] = 0;
          _emit();
        },
      );
    }

    if (removed.isNotEmpty) _emit();
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(
      GroupPendingJoinCounts(
        byGroupId:
            Map<String, int>.unmodifiable(Map<String, int>.from(_counts)),
        total: GroupPendingJoinBadgeLogic.sumGroupCounts(_counts),
      ),
    );
  }
}
