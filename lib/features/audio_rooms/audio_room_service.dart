import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Papéis que abrem/fecham a sala e aprovam quem fala (espelha o servidor).
bool audioRoomIsModeratorRole(String role) =>
    role == 'owner' || role == 'admin' || role == 'moderator';

class AudioRoomInfo {
  final String id;
  final String openedBy;
  final String openedByName;
  final int participantCount;
  final List<String> presentUids;
  final List<String> speakerUids;

  const AudioRoomInfo({
    required this.id,
    required this.openedBy,
    required this.openedByName,
    required this.participantCount,
    required this.presentUids,
    required this.speakerUids,
  });

  static List<String> _list(dynamic v) => v is List
      ? v.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
      : const <String>[];

  factory AudioRoomInfo.fromDoc(String id, Map<String, dynamic> d) =>
      AudioRoomInfo(
        id: id,
        openedBy: '${d['openedBy'] ?? ''}',
        openedByName: '${d['openedByName'] ?? ''}',
        participantCount: (d['participantCount'] is num)
            ? (d['participantCount'] as num).toInt()
            : 0,
        presentUids: _list(d['presentUids']),
        speakerUids: _list(d['speakerUids']),
      );
}

class AudioRoomHand {
  final String uid;
  final String name;
  const AudioRoomHand(this.uid, this.name);
}

class AudioRoomToken {
  final String token;
  final String url;
  final String roomId;
  final String role;
  final bool canPublish;
  const AudioRoomToken({
    required this.token,
    required this.url,
    required this.roomId,
    required this.role,
    required this.canPublish,
  });
}

/// Acesso às salas: leitura pelo Firestore, ações pela função audioRoomAction.
class AudioRoomService {
  AudioRoomService({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db,
        _functions = functions;

  final FirebaseFirestore? _db;
  final FirebaseFunctions? _functions;

  FirebaseFirestore get db => _db ?? FirebaseFirestore.instance;
  FirebaseFunctions get functions =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  CollectionReference<Map<String, dynamic>> _rooms(String groupId) =>
      db.collection('groups').doc(groupId).collection('audioRooms');

  /// Sala ao vivo do grupo (ou null).
  Stream<AudioRoomInfo?> liveRoom(String groupId) => _rooms(groupId)
      .where('status', isEqualTo: 'live')
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty
          ? null
          : AudioRoomInfo.fromDoc(s.docs.first.id, s.docs.first.data()));

  Stream<List<AudioRoomHand>> hands(String groupId, String roomId) =>
      _rooms(groupId).doc(roomId).collection('hands').snapshots().map((s) => s
          .docs
          .map((d) => AudioRoomHand(d.id, '${d.data()['name'] ?? ''}'))
          .toList());

  Future<Map<String, dynamic>> _call(
      String action, String groupId, [String? targetUid]) async {
    final res = await functions.httpsCallable('audioRoomAction').call({
      'action': action,
      'groupId': groupId,
      if (targetUid != null) 'targetUid': targetUid,
    });
    final data = res.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<void> open(String groupId) => _call('open', groupId);
  Future<void> close(String groupId) => _call('close', groupId);
  Future<void> raiseHand(String groupId) => _call('raiseHand', groupId);
  Future<void> lowerHand(String groupId, [String? uid]) =>
      _call('lowerHand', groupId, uid);
  Future<void> approveSpeaker(String groupId, String uid) =>
      _call('approveSpeaker', groupId, uid);
  Future<void> revokeSpeaker(String groupId, String uid) =>
      _call('revokeSpeaker', groupId, uid);

  Future<AudioRoomToken> token(String groupId) async {
    final d = await _call('token', groupId);
    return AudioRoomToken(
      token: '${d['token'] ?? ''}',
      url: '${d['url'] ?? ''}',
      roomId: '${d['roomId'] ?? ''}',
      role: '${d['role'] ?? 'member'}',
      canPublish: d['canPublish'] == true,
    );
  }

  /// Push "sala ao vivo" deste grupo (padrão: ligado).
  DocumentReference<Map<String, dynamic>> _pref(String uid, String groupId) =>
      db.collection('users').doc(uid).collection('groupPrefs').doc(groupId);

  Stream<bool> livePushEnabled(String uid, String groupId) => _pref(uid, groupId)
      .snapshots()
      .map((s) => s.data()?['audioRoomPush'] != false);

  Future<void> setLivePushEnabled(String uid, String groupId, bool on) =>
      _pref(uid, groupId).set({
        'audioRoomPush': on,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

/// Código de erro do servidor para a chave de texto da interface.
String audioRoomErrorKey(Object error) {
  if (error is FirebaseFunctionsException) {
    final m = error.message ?? '';
    if (m == 'room_full') return 'audio_room_full';
    if (m == 'no_live_room') return 'audio_room_ended';
  }
  return 'audio_room_error';
}
