import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../services/group_role_policy.dart';
import 'audio_room_service.dart';

/// Uma pessoa na sala, como a tela mostra.
class AudioRoomPeer {
  final String uid;
  final String name;
  final bool isLocal;
  final bool canSpeak;
  final bool micOn;
  final bool speaking;
  const AudioRoomPeer({
    required this.uid,
    required this.name,
    required this.isLocal,
    required this.canSpeak,
    required this.micOn,
    required this.speaking,
  });
}

/// Mantém a conexão com a sala enquanto a pessoa navega pelo app
/// (o botão Mensagem volta pro chat sem sair da sala).
class AudioRoomController extends ChangeNotifier {
  AudioRoomController._();
  static final AudioRoomController instance = AudioRoomController._();

  final AudioRoomService service = AudioRoomService();

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  String? groupId;
  String? roomId;
  String role = 'member';
  bool connecting = false;
  Map<String, dynamic> _groupData = const {};

  /// Pedido de "mutar" mandado por dono/admin/moderador pela sala.
  static const String muteTopic = 'remdy_mute';

  /// Avisos para a tela mostrar (chave de texto).
  final StreamController<String> _notices =
      StreamController<String>.broadcast();
  Stream<String> get notices => _notices.stream;

  bool get connected => _room != null && groupId != null;
  bool isInGroup(String gid) => connected && groupId == gid;
  bool get isModerator => audioRoomIsModeratorRole(role);

  bool get canPublish =>
      _room?.localParticipant?.permissions.canPublish ?? false;
  bool get micOn => _room?.localParticipant?.isMicrophoneEnabled() ?? false;

  List<AudioRoomPeer> get peers {
    final room = _room;
    if (room == null) return const [];
    final out = <AudioRoomPeer>[];
    final local = room.localParticipant;
    if (local != null) out.add(_peer(local, true));
    for (final p in room.remoteParticipants.values) {
      out.add(_peer(p, false));
    }
    return out;
  }

  AudioRoomPeer _peer(Participant p, bool isLocal) => AudioRoomPeer(
        uid: p.identity,
        name: p.name.isNotEmpty ? p.name : p.identity,
        isLocal: isLocal,
        canSpeak: p.permissions.canPublish,
        micOn: p.isMicrophoneEnabled(),
        speaking: p.isSpeaking,
      );

  /// Entra na sala ao vivo do grupo. Lança erro para a tela mostrar.
  Future<void> join(String gid,
      {Map<String, dynamic> groupData = const {}}) async {
    if (isInGroup(gid) || connecting) return;
    if (connected) await leave();
    connecting = true;
    notifyListeners();
    try {
      final t = await service.token(gid);
      final room = Room(
        roomOptions: const RoomOptions(adaptiveStream: false, dynacast: false),
      );
      final listener = room.createListener();
      listener
        ..on<RoomDisconnectedEvent>((_) => _cleanup())
        ..on<ParticipantPermissionsUpdatedEvent>((e) async {
          // Perdeu a palavra: desliga o microfone.
          if (e.participant is LocalParticipant &&
              !e.participant.permissions.canPublish) {
            try {
              await room.localParticipant?.setMicrophoneEnabled(false);
            } catch (_) {}
          }
          notifyListeners();
        });
      listener.on<DataReceivedEvent>((e) => _onData(room, e));
      room.addListener(notifyListeners);
      await room.connect(t.url, t.token);
      _room = room;
      _listener = listener;
      groupId = gid;
      roomId = t.roomId;
      role = t.role;
      _groupData = groupData;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> setMic(bool on) async {
    final local = _room?.localParticipant;
    if (local == null) return;
    if (on && !canPublish) return;
    await local.setMicrophoneEnabled(on);
    notifyListeners();
  }

  String _roleOf(String uid) => GroupRolePolicy.roleOf(_groupData, uid);

  /// Dono, admin e moderadores mutam qualquer um, menos a si mesmos;
  /// só o dono pode mutar outro dono.
  bool canMute(String uid) {
    final me = _room?.localParticipant?.identity ?? '';
    if (!isModerator || uid.isEmpty || uid == me) return false;
    return role == 'owner' || _roleOf(uid) != 'owner';
  }

  Future<void> _sendMute(String to, {List<String>? only}) async {
    final local = _room?.localParticipant;
    if (local == null || !isModerator) return;
    await local.publishData(
      utf8.encode(jsonEncode({'to': to})),
      reliable: true,
      topic: muteTopic,
      destinationIdentities: only,
    );
  }

  /// Desliga o microfone de uma pessoa. Ela pode ligar de novo.
  Future<void> mute(String uid) async {
    if (!canMute(uid)) return;
    await _sendMute(uid, only: [uid]);
  }

  /// Desliga o microfone de todos na sala, menos o de quem pediu.
  Future<void> muteAll() => _sendMute('*');

  Future<void> _onData(Room room, DataReceivedEvent e) async {
    if (e.topic != muteTopic) return;
    final from = e.participant?.identity ?? '';
    final fromRole = _roleOf(from);
    // Só vale pedido de dono, admin ou moderador do grupo.
    if (!audioRoomIsModeratorRole(fromRole)) return;
    final local = room.localParticipant;
    if (local == null || from == local.identity) return;
    String to = '';
    try {
      to = '${(jsonDecode(utf8.decode(e.data)) as Map)['to'] ?? ''}';
    } catch (_) {
      return;
    }
    if (to != '*' && to != local.identity) return;
    if (role == 'owner' && fromRole != 'owner') return;
    if (!local.isMicrophoneEnabled()) return;
    try {
      await local.setMicrophoneEnabled(false);
    } catch (_) {}
    _notices.add('audio_room_muted_by_mod');
    notifyListeners();
  }

  Future<void> leave() async {
    final room = _room;
    final gid = groupId;
    if (gid != null && !isModerator) {
      // Sai da fila de quem pediu a palavra, se estiver nela.
      unawaited(service.lowerHand(gid).catchError((_) {}));
    }
    _cleanup();
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {}
      await room.dispose();
    }
  }

  void _cleanup() {
    _room?.removeListener(notifyListeners);
    _listener?.dispose();
    _listener = null;
    _room = null;
    groupId = null;
    roomId = null;
    role = 'member';
    _groupData = const {};
    notifyListeners();
  }
}
