import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'block_report_logic.dart';

/// Single reactive source for **who I blocked** (local hide, not global delete).
class BlockVisibility {
  BlockVisibility._();

  static final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static String? _attachedUid;
  static Set<String> _mine = {};

  static Set<String> get mine => Set<String>.unmodifiable(_mine);

  /// Current snapshot, then live updates (optimistic + Firestore).
  static Stream<Set<String>> get mineStream async* {
    yield mine;
    yield* _controller.stream;
  }

  static bool hidesGroupSender({
    required String senderId,
    required String? myUid,
    Set<String>? blocked,
  }) {
    final sender = senderId.trim();
    if (sender.isEmpty) return false;
    if (myUid != null && sender == myUid) return false;
    return (blocked ?? _mine).contains(sender);
  }

  static bool hidesUid(String? uid, {Set<String>? blocked}) {
    final id = (uid ?? '').trim();
    if (id.isEmpty) return false;
    return (blocked ?? _mine).contains(id);
  }

  static Set<String> parse(dynamic raw) =>
      BlockReportLogic.blockedUids(raw).toSet();

  static String? peerUid(dynamic participants, String myUid) {
    if (participants is! List) return null;
    for (final raw in participants) {
      final id = raw.toString().trim();
      if (id.isNotEmpty && id != myUid) return id;
    }
    return null;
  }

  static bool hidesConversation({
    required Map<String, dynamic> data,
    required String myUid,
    Set<String>? blocked,
  }) {
    final set = blocked ?? _mine;
    final peer = peerUid(data['participants'], myUid);
    return peer != null && set.contains(peer);
  }

  static String eventAuthorUid(Map<String, dynamic> data) =>
      (data['createdBy'] ??
              data['organizerId'] ??
              data['ownerId'] ??
              data['userId'] ??
              '')
          .toString()
          .trim();

  static bool hidesEventAuthor(String createdBy, {Set<String>? blocked}) {
    final id = createdBy.trim();
    if (id.isEmpty) return false;
    return (blocked ?? _mine).contains(id);
  }

  static bool hidesEventMap(Map<String, dynamic> data, {Set<String>? blocked}) =>
      hidesEventAuthor(eventAuthorUid(data), blocked: blocked);

  static void attach(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return;
    if (_attachedUid == id && _sub != null) return;
    detach(clear: false);
    _attachedUid = id;
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(id)
        .snapshots()
        .listen((snap) {
      _emit(parse(snap.data()?['blocked']));
    });
  }

  static void detach({bool clear = true}) {
    _sub?.cancel();
    _sub = null;
    _attachedUid = null;
    if (clear) _emit({});
  }

  /// Instant UI update after a local block, before the snapshot arrives.
  static void noteBlocked(String otherUid) {
    final id = otherUid.trim();
    if (id.isEmpty) return;
    _emit({..._mine, id});
  }

  static void noteUnblocked(String otherUid) {
    final id = otherUid.trim();
    if (id.isEmpty) return;
    final next = {..._mine}..remove(id);
    _emit(next);
  }

  static void _emit(Set<String> next) {
    if (setEquals(_mine, next)) return;
    _mine = Set<String>.from(next);
    if (!_controller.isClosed) {
      _controller.add(Set<String>.unmodifiable(_mine));
    }
  }

  @visibleForTesting
  static void debugReplace(Set<String> uids) => _emit(uids);
}
