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

/// Mensagem do chat da sala. Só existe na memória de quem está na sala:
/// nada é salvo, e tudo some quando a sala acaba.
class AudioRoomChatMessage {
  final String id;
  final String uid;
  final String name;
  final String text;
  final int ts;
  const AudioRoomChatMessage({
    required this.id,
    required this.uid,
    required this.name,
    required this.text,
    required this.ts,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'uid': uid, 'name': name, 'text': text, 'ts': ts};

  static AudioRoomChatMessage? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = '${j['id'] ?? ''}';
    final text = '${j['text'] ?? ''}';
    if (id.isEmpty || text.trim().isEmpty) return null;
    return AudioRoomChatMessage(
      id: id,
      uid: '${j['uid'] ?? ''}',
      name: '${j['name'] ?? ''}',
      text: text.length > AudioRoomController.chatMaxChars
          ? text.substring(0, AudioRoomController.chatMaxChars)
          : text,
      ts: j['ts'] is int ? j['ts'] as int : 0,
    );
  }
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

  static const String chatTopic = 'remdy_chat';
  static const String chatDeleteTopic = 'remdy_chat_del';
  static const String chatSyncTopic = 'remdy_chat_sync';
  static const int chatMaxChars = 500;
  static const int _chatKeep = 200;

  final List<AudioRoomChatMessage> chat = [];
  int chatUnread = 0;
  bool _chatOpen = false;

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
      listener
        ..on<DataReceivedEvent>((e) => _onData(room, e))
        ..on<ParticipantConnectedEvent>(
            (e) => _sendHistory(e.participant.identity));
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
    if (e.topic == chatTopic ||
        e.topic == chatDeleteTopic ||
        e.topic == chatSyncTopic) {
      _onChatData(e);
      return;
    }
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

  // ---------- Chat da sala ----------

  void setChatOpen(bool open) {
    _chatOpen = open;
    if (open && chatUnread != 0) {
      chatUnread = 0;
      notifyListeners();
    }
  }

  void _addChat(AudioRoomChatMessage m, {bool countUnread = true}) {
    if (chat.any((x) => x.id == m.id)) return;
    chat.add(m);
    chat.sort((a, b) => a.ts.compareTo(b.ts));
    if (chat.length > _chatKeep) chat.removeRange(0, chat.length - _chatKeep);
    if (countUnread && !_chatOpen) chatUnread++;
  }

  Future<void> sendChat(String raw) async {
    final local = _room?.localParticipant;
    var text = raw.trim();
    if (local == null || text.isEmpty) return;
    if (text.length > chatMaxChars) text = text.substring(0, chatMaxChars);
    final now = DateTime.now().millisecondsSinceEpoch;
    final m = AudioRoomChatMessage(
      id: '${local.identity}_$now',
      uid: local.identity,
      name: local.name.isNotEmpty ? local.name : local.identity,
      text: text,
      ts: now,
    );
    await local.publishData(utf8.encode(jsonEncode(m.toJson())),
        reliable: true, topic: chatTopic);
    _addChat(m, countUnread: false);
    notifyListeners();
  }

  /// Dono, admin e moderadores apagam qualquer mensagem, para todos.
  Future<void> deleteChat(String id) async {
    final local = _room?.localParticipant;
    if (local == null || !isModerator) return;
    await local.publishData(utf8.encode(jsonEncode({'id': id})),
        reliable: true, topic: chatDeleteTopic);
    chat.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  /// Quem chega depois recebe as mensagens anteriores de um moderador
  /// que já está na sala (o de menor id, pra não chegar repetido).
  Future<void> _sendHistory(String to) async {
    final room = _room;
    final local = room?.localParticipant;
    if (room == null || local == null || !isModerator || chat.isEmpty) return;
    final mods = <String>[
      local.identity,
      for (final p in room.remoteParticipants.values)
        if (p.identity != to && audioRoomIsModeratorRole(_roleOf(p.identity)))
          p.identity,
    ]..sort();
    if (mods.first != local.identity) return;
    for (var i = 0; i < chat.length; i += 10) {
      final part = chat.skip(i).take(10).map((m) => m.toJson()).toList();
      try {
        await local.publishData(utf8.encode(jsonEncode({'list': part})),
            reliable: true, topic: chatSyncTopic, destinationIdentities: [to]);
      } catch (_) {}
    }
  }

  void _onChatData(DataReceivedEvent e) {
    final sender = e.participant;
    if (sender == null) return;
    Object? body;
    try {
      body = jsonDecode(utf8.decode(e.data));
    } catch (_) {
      return;
    }
    if (body is! Map) return;
    final Map data = body;
    final fromMod = audioRoomIsModeratorRole(_roleOf(sender.identity));
    if (e.topic == chatTopic) {
      final m = AudioRoomChatMessage.fromJson(body);
      if (m == null) return;
      // Nome e autor vêm da sala, não do texto recebido.
      _addChat(AudioRoomChatMessage(
        id: m.id,
        uid: sender.identity,
        name: sender.name.isNotEmpty ? sender.name : sender.identity,
        text: m.text,
        ts: m.ts,
      ));
    } else if (e.topic == chatDeleteTopic) {
      if (!fromMod) return;
      final id = '${data['id'] ?? ''}';
      chat.removeWhere((m) => m.id == id);
    } else if (e.topic == chatSyncTopic) {
      if (!fromMod) return;
      final list = data['list'];
      if (list is! List) return;
      for (final j in list) {
        final m = AudioRoomChatMessage.fromJson(j);
        if (m != null) _addChat(m, countUnread: false);
      }
    }
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
    chat.clear();
    chatUnread = 0;
    _chatOpen = false;
    notifyListeners();
  }
}
