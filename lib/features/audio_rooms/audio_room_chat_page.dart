import 'package:flutter/material.dart';

import '../../l10n/app_texts.dart';
import '../../widgets/chat_composer_text.dart';
import 'audio_room_controller.dart';

const Color _text = Color(0xFF111827);
const Color _muted = Color(0xFF6B7280);
const Color _border = Color(0xFFE5E7EB);
const Color _remdyBlue = Color(0xFF313A5F);

/// Chat só da sala de áudio. Todos na sala escrevem, inclusive ouvintes;
/// nada fica salvo e tudo some quando a sala acaba.
class AudioRoomChatPage extends StatefulWidget {
  final String groupName;
  const AudioRoomChatPage({super.key, required this.groupName});

  @override
  State<AudioRoomChatPage> createState() => _AudioRoomChatPageState();
}

class _AudioRoomChatPageState extends State<AudioRoomChatPage> {
  final AudioRoomController _c = AudioRoomController.instance;
  final TextEditingController _textC = TextEditingController();
  bool _wasConnected = false;

  @override
  void initState() {
    super.initState();
    _wasConnected = _c.connected;
    _c.setChatOpen(true);
    _c.addListener(_onChange);
    _textC.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.setChatOpen(false);
    _textC.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    if (_wasConnected && !_c.connected) {
      Navigator.of(context).maybePop();
      return;
    }
    _c.setChatOpen(true);
    setState(() {});
  }

  Future<void> _send() async {
    final text = _textC.text;
    if (!ChatComposerText.hasSendableText(text)) return;
    _textC.clear();
    try {
      await _c.sendChat(text);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppTexts.t('chat_send_failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AudioRoomChatView(
      groupName: widget.groupName,
      messages: List.of(_c.chat),
      myUid: _c.peers
          .where((p) => p.isLocal)
          .map((p) => p.uid)
          .followedBy(const ['']).first,
      isModerator: _c.isModerator,
      controller: _textC,
      onSend: _send,
      onDelete: (id) => _c.deleteChat(id),
    );
  }
}

/// Parte visual do chat da sala (usada também nos prints).
class AudioRoomChatView extends StatelessWidget {
  final String groupName;
  final List<AudioRoomChatMessage> messages;
  final String myUid;
  final bool isModerator;
  final TextEditingController controller;
  final VoidCallback onSend;
  final void Function(String id) onDelete;

  const AudioRoomChatView({
    super.key,
    required this.groupName,
    required this.messages,
    required this.myUid,
    required this.isModerator,
    required this.controller,
    required this.onSend,
    required this.onDelete,
  });

  String _time(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _actions(BuildContext context, AppTexts t, AudioRoomChatMessage m) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.delete_outline, color: _remdyBlue),
            title: Text(t.get('audio_room_chat_delete'),
                style:
                    const TextStyle(color: _text, fontWeight: FontWeight.w700)),
            onTap: () {
              Navigator.pop(ctx);
              onDelete(m.id);
            },
          ),
        ]),
      ),
    );
  }

  Widget _bubble(BuildContext context, AppTexts t, AudioRoomChatMessage m) {
    final isMe = m.uid == myUid;
    final bg = isMe ? _remdyBlue : Colors.white;
    final fg = isMe ? Colors.white : _text;
    final timeColor = isMe ? Colors.white70 : _muted;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: isModerator ? () => _actions(context, t, m) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          constraints: const BoxConstraints(maxWidth: 290),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isMe ? _remdyBlue : _border),
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Text(m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _remdyBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              Text(m.text, style: TextStyle(color: fg, fontSize: 15)),
              const SizedBox(height: 4),
              Text(_time(m.ts),
                  style: TextStyle(
                      color: timeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final canSend = ChatComposerText.hasSendableText(controller.text);
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
            Text(t.get('audio_room_chat'),
                style: const TextStyle(
                    color: _text, fontWeight: FontWeight.w800, fontSize: 16)),
            Text(groupName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _muted, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Text(t.get('audio_room_chat_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _muted, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Text(t.get('audio_room_chat_empty'),
                      style: const TextStyle(
                          color: _muted, fontWeight: FontWeight.w700)),
                )
              : ListView.builder(
                  reverse: true,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (_, i) =>
                      _bubble(context, t, messages[messages.length - 1 - i]),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: AudioRoomController.chatMaxChars,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: ChatComposerText.keyboardCapitalization,
                    inputFormatters: [
                      ChatComposerText.leadingAlphaCapitalizationFormatter,
                    ],
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: t.get('audio_room_chat_type'),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: canSend ? onSend : null,
                borderRadius: BorderRadius.circular(999),
                child: Opacity(
                  opacity: canSend ? 1 : 0.5,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _remdyBlue,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child:
                        const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
