import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

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
  Future<void> join(String gid) async {
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
      room.addListener(notifyListeners);
      await room.connect(t.url, t.token);
      _room = room;
      _listener = listener;
      groupId = gid;
      roomId = t.roomId;
      role = t.role;
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
    notifyListeners();
  }
}
