import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../widgets/chat_composer_text.dart';

import '../../l10n/app_texts.dart';
import '../../services/group_role_policy.dart';
import 'audio_room_avatar.dart';
import 'audio_room_float_chat.dart';
import 'audio_room_controller.dart';
import 'audio_room_service.dart';

const Color _text = Color(0xFF111827);
const Color _muted = Color(0xFF6B7280);
const Color _border = Color(0xFFE5E7EB);
const Color _remdyBlue = Color(0xFF313A5F);

/// Tela da sala de áudio: lista vertical de quem está na sala.
class AudioRoomPage extends StatefulWidget {
  final String groupId;
  final String groupName;
  final Map<String, dynamic> groupData;

  const AudioRoomPage({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.groupData,
  });

  @override
  State<AudioRoomPage> createState() => _AudioRoomPageState();
}

class _AudioRoomPageState extends State<AudioRoomPage> {
  final AudioRoomController _c = AudioRoomController.instance;
  AudioRoomService get _svc => _c.service;
  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _busy = false;
  StreamSubscription<String>? _noticeSub;
  bool _composerOpen = false;
  final TextEditingController _textC = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    _noticeSub = _c.notices.listen(_toast);
    if (!_c.isInGroup(widget.groupId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _join());
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _noticeSub?.cancel();
    _textC.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    // Sala encerrada ou conexão perdida depois de entrar.
    if (!_c.connected && !_c.connecting && _joinedOnce) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  bool _joinedOnce = false;

  void _toast(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppTexts.t(key))));
  }

  Future<void> _join() async {
    try {
      await _c.join(widget.groupId, groupData: widget.groupData);
      _joinedOnce = true;
    } catch (e) {
      _toast(audioRoomErrorKey(e));
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      _toast(audioRoomErrorKey(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMic() => _run(() async {
        try {
          await _c.setMic(!_c.micOn);
        } catch (_) {
          _toast('audio_room_mic_denied');
        }
      });

  void _toggleComposer() {
    setState(() => _composerOpen = !_composerOpen);
    if (_composerOpen) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focus.requestFocus());
    } else {
      _focus.unfocus();
    }
  }

  Future<void> _sendChat(String text) async {
    if (!ChatComposerText.hasSendableText(text)) return;
    final isTyped = text == _textC.text;
    try {
      await _c.sendChat(text);
      if (isTyped) _textC.clear();
    } catch (_) {
      _toast('chat_send_failed');
    }
  }

  Future<void> _leave() async {
    await _c.leave();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _close() async {
    final t = AppTexts.current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t.get('audio_room_close_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.get('audio_room_close')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _svc.close(widget.groupId));
    await _leave();
  }

  String _roleLabel(String uid) {
    final t = AppTexts.current;
    final r = GroupRolePolicy.roleOf(widget.groupData, uid);
    if (r == 'owner') return t.get('audio_room_owner');
    if (r == 'admin' || r == 'moderator') return t.get('audio_room_moderator');
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final peers = _c.isInGroup(widget.groupId) ? _c.peers : <AudioRoomPeer>[];
    final roomId = _c.roomId;
    Widget view(List<AudioRoomHand> hands) => AudioRoomView(
          groupName: widget.groupName,
          peers: peers,
          roleLabelOf: _roleLabel,
          isModerator: _c.isModerator,
          loading: _c.connecting && peers.isEmpty,
          hands: _c.isModerator ? hands : const [],
          myHandRaised: hands.any((h) => h.uid == _myUid),
          canSpeak: _c.canPublish,
          micOn: _c.micOn,
          busy: _busy,
          onApprove: (uid) =>
              _run(() => _svc.approveSpeaker(widget.groupId, uid)),
          onRevoke: (uid) =>
              _run(() => _svc.revokeSpeaker(widget.groupId, uid)),
          canMuteOf: _c.canMute,
          onMute: (uid) => _run(() => _c.mute(uid)),
          onMuteAll: () => _run(() async {
            await _c.muteAll();
            _toast('audio_room_muted_all');
          }),
          onToggleHand: (raised) => _run(() => raised
              ? _svc.lowerHand(widget.groupId)
              : _svc.raiseHand(widget.groupId)),
          onToggleMic: _toggleMic,
          onMessage: _toggleComposer,
          onGroupChat: () => Navigator.of(context).maybePop(),
          chatMessages: List.of(_c.chat),
          onDeleteChat: (id) => _c.deleteChat(id),
          composer: _composerOpen
              ? AudioRoomComposer(
                  controller: _textC,
                  focusNode: _focus,
                  onSend: _sendChat,
                  onClose: _toggleComposer,
                )
              : null,
          onLeave: _leave,
          onClose: _close,
        );
    if (roomId == null) return view(const []);
    return StreamBuilder<List<AudioRoomHand>>(
      stream: _svc.hands(widget.groupId, roomId),
      builder: (context, snap) => view(snap.data ?? const <AudioRoomHand>[]),
    );
  }
}

/// Parte visual da sala, sem Firebase nem LiveKit (usada também nos prints).
class AudioRoomView extends StatelessWidget {
  final String groupName;
  final List<AudioRoomPeer> peers;
  final String Function(String uid) roleLabelOf;
  final bool isModerator;
  final bool loading;
  final List<AudioRoomHand> hands;
  final bool myHandRaised;
  final bool canSpeak;
  final bool micOn;
  final bool busy;
  final void Function(String uid) onApprove;
  final void Function(String uid) onRevoke;
  final bool Function(String uid) canMuteOf;
  final void Function(String uid) onMute;
  final VoidCallback onMuteAll;
  final void Function(bool raised) onToggleHand;
  final VoidCallback onToggleMic;
  final VoidCallback onMessage;
  final VoidCallback onGroupChat;
  final List<AudioRoomChatMessage> chatMessages;
  final void Function(String id) onDeleteChat;
  final Widget? composer;
  final bool animateChat;
  final VoidCallback onLeave;
  final VoidCallback onClose;

  const AudioRoomView({
    super.key,
    required this.groupName,
    required this.peers,
    required this.roleLabelOf,
    required this.isModerator,
    required this.loading,
    required this.hands,
    required this.myHandRaised,
    required this.canSpeak,
    required this.micOn,
    required this.busy,
    required this.onApprove,
    required this.onRevoke,
    required this.canMuteOf,
    required this.onMute,
    required this.onMuteAll,
    required this.onToggleHand,
    required this.onToggleMic,
    required this.onMessage,
    required this.onGroupChat,
    required this.chatMessages,
    required this.onDeleteChat,
    this.composer,
    this.animateChat = true,
    required this.onLeave,
    required this.onClose,
  });

  Widget _micIcon(AudioRoomPeer p) {
    if (p.canSpeak && p.micOn) {
      return Icon(Icons.mic_rounded,
          color: p.speaking ? Colors.green : Colors.green.shade400, size: 22);
    }
    return const Icon(Icons.mic_off_rounded, color: _muted, size: 22);
  }

  void _peerActions(BuildContext context, AppTexts t, AudioRoomPeer p,
      bool canMute, bool canRevoke) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: AudioRoomAvatar(uid: p.uid, name: p.name),
            title: Text(p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _text, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          const Divider(height: 1, color: _border),
          if (canMute)
            ListTile(
              leading: const Icon(Icons.mic_off_rounded, color: _remdyBlue),
              title: Text(t.get('audio_room_mute'),
                  style: const TextStyle(
                      color: _text, fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(ctx);
                onMute(p.uid);
              },
            ),
          if (canRevoke)
            ListTile(
              leading: const Icon(Icons.back_hand_outlined, color: _remdyBlue),
              title: Text(t.get('audio_room_revoke'),
                  style: const TextStyle(
                      color: _text, fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(ctx);
                onRevoke(p.uid);
              },
            ),
        ]),
      ),
    );
  }

  Widget _peerTile(BuildContext context, AppTexts t, AudioRoomPeer p) {
    final role = roleLabelOf(p.uid);
    final canRevoke = isModerator && !p.isLocal && p.canSpeak && role.isEmpty;
    final canMute =
        isModerator && !p.isLocal && p.canSpeak && p.micOn && canMuteOf(p.uid);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: AudioRoomAvatar(uid: p.uid, name: p.name),
      title: Text(
        p.isLocal ? '${p.name} (${t.get('audio_room_you')})' : p.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            color: _text, fontWeight: FontWeight.w700, fontSize: 15),
      ),
      subtitle: Text(
        role.isNotEmpty
            ? role
            : (p.canSpeak
                ? t.get('audio_room_speaker')
                : t.get('audio_room_listening')),
        style: TextStyle(
          color: role.isNotEmpty ? _remdyBlue : _muted,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
      trailing: _micIcon(p),
      onTap: (canMute || canRevoke)
          ? () => _peerActions(context, t, p, canMute, canRevoke)
          : null,
      onLongPress: canRevoke ? () => onRevoke(p.uid) : null,
    );
  }

  Widget _handsStrip(AppTexts t) {
    final title = hands.length == 1
        ? t.get('audio_room_request_one')
        : t.get('audio_room_requests').replaceAll('{count}', '${hands.length}');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.back_hand_rounded, color: _remdyBlue, size: 18),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: _text, fontWeight: FontWeight.w800, fontSize: 14)),
          ]),
          for (final h in hands)
            Row(children: [
              Expanded(
                child: Text(h.name.isEmpty ? h.uid : h.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _text, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: busy ? null : () => onApprove(h.uid),
                child: Text(t.get('audio_room_approve'),
                    style: const TextStyle(
                        color: _remdyBlue, fontWeight: FontWeight.w800)),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap,
      {bool active = false}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                color: onTap == null ? _border : (active ? _remdyBlue : _muted),
                size: 26),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: active ? _remdyBlue : _muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        foregroundColor: _text,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(groupName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _text, fontWeight: FontWeight.w800, fontSize: 16)),
            Row(children: [
              const Icon(Icons.circle, size: 8, color: Colors.red),
              const SizedBox(width: 6),
              Text(
                '${t.get('audio_room_live')} · ${t.get('audio_room_participants').replaceAll('{count}', '${peers.length}')}',
                style: const TextStyle(
                    color: _muted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ]),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t.get('audio_room_group_chat'),
            onPressed: onGroupChat,
            icon: const Icon(Icons.forum_outlined, color: _muted),
          ),
          if (isModerator)
            TextButton(
              onPressed: busy ? null : onClose,
              child: Text(t.get('audio_room_close'),
                  style: const TextStyle(
                      color: _remdyBlue, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: _remdyBlue))
          : Column(children: [
              if (isModerator && hands.isNotEmpty) _handsStrip(t),
              Expanded(
                child: Stack(children: [
                  Positioned.fill(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(top: 8, bottom: 96),
                      itemCount: peers.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: _border, indent: 72),
                      itemBuilder: (_, i) => _peerTile(context, t, peers[i]),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: AudioRoomFloatingMessages(
                      messages: chatMessages,
                      isModerator: isModerator,
                      onDelete: onDeleteChat,
                      animate: animateChat,
                    ),
                  ),
                ]),
              ),
              if (composer != null) composer!,
            ]),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _border)),
          ),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(children: [
            if (!canSpeak)
              _action(
                Icons.back_hand_rounded,
                myHandRaised
                    ? t.get('audio_room_lower_hand')
                    : t.get('audio_room_raise_hand'),
                busy ? null : () => onToggleHand(myHandRaised),
                active: myHandRaised,
              )
            else
              _action(
                micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                t.get('audio_room_mic'),
                busy ? null : onToggleMic,
                active: micOn,
              ),
            if (isModerator)
              _action(Icons.volume_off_rounded, t.get('audio_room_mute_all'),
                  busy ? null : onMuteAll),
            _action(Icons.chat_bubble_outline_rounded,
                t.get('audio_room_message'), onMessage,
                active: composer != null),
            _action(Icons.logout_rounded, t.get('audio_room_leave'), onLeave),
          ]),
        ),
      ),
    );
  }
}

/// Abre (dono/moderador) e entra na sala do grupo.
Future<void> openAndEnterAudioRoom(
  BuildContext context, {
  required String groupId,
  required String groupName,
  required Map<String, dynamic> groupData,
  bool create = false,
}) async {
  final c = AudioRoomController.instance;
  if (create) {
    try {
      await c.service.open(groupId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppTexts.t(audioRoomErrorKey(e)))));
      }
      return;
    }
  }
  if (!context.mounted) return;
  unawaited(Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => AudioRoomPage(
      groupId: groupId,
      groupName: groupName,
      groupData: groupData,
    ),
  )));
}
