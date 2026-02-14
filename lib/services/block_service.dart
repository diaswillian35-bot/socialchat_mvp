import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BlockService {
  static final _db = FirebaseFirestore.instance;

  static String? get myUid => FirebaseAuth.instance.currentUser?.uid;

  // users/{myUid}.blocked = [otherUid, ...]
  static Future<void> blockUser(String otherUid) async {
    final uid = myUid;
    if (uid == null) return;

    await _db.collection('users').doc(uid).set({
      'blocked': FieldValue.arrayUnion([otherUid]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> unblockUser(String otherUid) async {
    final uid = myUid;
    if (uid == null) return;

    await _db.collection('users').doc(uid).set({
      'blocked': FieldValue.arrayRemove([otherUid]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Stream: "EU bloqueei essa pessoa?"
  static Stream<bool> isBlockedStream(String otherUid) {
    final uid = myUid;
    if (uid == null) return Stream<bool>.value(false);

    return _db.collection('users').doc(uid).snapshots().map((doc) {
      final data = doc.data() ?? {};
      final list = data['blocked'];
      if (list is List) {
        return list.map((e) => e.toString()).contains(otherUid);
      }
      return false;
    }).distinct();
  }

  // Future: "EU bloqueei OU ELE me bloqueou?"
  static Future<bool> isEitherBlocked(String otherUid) async {
    final me = myUid;
    if (me == null) return false;

    // Eu bloqueei ele?
    final meSnap = await _db.collection('users').doc(me).get();
    final meData = meSnap.data() ?? {};
    final myBlocked = meData['blocked'] is List
        ? List<String>.from(meData['blocked'])
        : <String>[];
    if (myBlocked.contains(otherUid)) return true;

    // Ele me bloqueou?
    final otherSnap = await _db.collection('users').doc(otherUid).get();
    final otherData = otherSnap.data() ?? {};
    final otherBlocked = otherData['blocked'] is List
        ? List<String>.from(otherData['blocked'])
        : <String>[];

    return otherBlocked.contains(me);
  }

  // Stream: "EU bloqueei OU ELE me bloqueou?" (em tempo real)
  static Stream<bool> isEitherBlockedStream(String otherUid) {
    final me = myUid;
    if (me == null) return Stream<bool>.value(false);

    bool meBlocks = false;
    bool otherBlocks = false;

    bool hasBlocked(DocumentSnapshot<Map<String, dynamic>> doc, String target) {
      final data = doc.data() ?? {};
      final list = data['blocked'];
      if (list is List) {
        return list.map((e) => e.toString()).contains(target);
      }
      return false;
    }

    final meStream = _db.collection('users').doc(me).snapshots().map((doc) {
      meBlocks = hasBlocked(doc, otherUid);
      return meBlocks || otherBlocks;
    });

    final otherStream =
        _db.collection('users').doc(otherUid).snapshots().map((doc) {
      otherBlocks = hasBlocked(doc, me);
      return meBlocks || otherBlocks;
    });

    // Junta os dois streams
    return Stream<bool>.multi((controller) {
      StreamSubscription? s1;
      StreamSubscription? s2;

      void emit(bool v) {
        if (!controller.isClosed) controller.add(v);
      }

      s1 = meStream.listen(emit);
      s2 = otherStream.listen(emit);

      controller.onCancel = () async {
        await s1?.cancel();
        await s2?.cancel();
      };
    }).distinct();
  }
}