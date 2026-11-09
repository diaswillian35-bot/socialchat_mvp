import 'package:flutter/material.dart';

import '../../l10n/app_texts.dart';
import '../../widgets/chat_composer_text.dart';
import 'audio_room_controller.dart';

const Color _text = Color(0xFF111827);
const Color _border = Color(0xFFE5E7EB);
const Color _remdyBlue = Color(0xFF313A5F);

/// Emojis rápidos da caixinha de mensagem da sala.
const List<String> audioRoomQuickEmojis = [
  '👏',
  '❤️',
  '😂',
  '🔥',
  '👍',
  '🎉',
  '😮',
  '🙏',
];

bool audioRoomIsQuickEmoji(String text) =>
    audioRoomQuickEmojis.contains(text.trim());

/// Mensagens flutuando por cima da sala. Cada uma aparece, fica alguns
/// segundos e some sozinha; nada é salvo.
class AudioRoomFloatingMessages extends StatelessWidget {
  final List<AudioRoomChatMessage> messages;
  final bool animate;
  final bool isModerator;
  final void Function(String id) onDelete;

  const AudioRoomFloatingMessages({
    super.key,
    required this.messages,
    required this.isModerator,
    required this.onDelete,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final shown =
        messages.length > 5 ? messages.sublist(messages.length - 5) : messages;
    return IgnorePointer(
      ignoring: !isModerator,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in shown)
            _Floating(
              key: ValueKey(m.id),
              animate: animate,
              child: GestureDetector(
                onLongPress:
                    isModerator ? () => _confirmDelete(context, m) : null,
                child: _bubble(m),
              ),
            ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, AudioRoomChatMessage m) {
    final t = AppTexts.current;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline, color: _remdyBlue),
          title: Text(t.get('audio_room_chat_delete'),
              style:
                  const TextStyle(color: _text, fontWeight: FontWeight.w700)),
          onTap: () {
            Navigator.pop(ctx);
            onDelete(m.id);
          },
        ),
      ),
    );
  }

  Widget _bubble(AudioRoomChatMessage m) {
    final emoji = audioRoomIsQuickEmoji(m.text);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      constraints: const BoxConstraints(maxWidth: 290),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: emoji
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _remdyBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Text(m.text.trim(), style: const TextStyle(fontSize: 26)),
            ])
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _remdyBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
                Text(m.text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _text, fontSize: 15)),
              ],
            ),
    );
  }
}

/// Aparece subindo, fica e some aos poucos no fim do tempo da mensagem.
class _Floating extends StatefulWidget {
  final Widget child;
  final bool animate;
  const _Floating({super.key, required this.child, required this.animate});

  @override
  State<_Floating> createState() => _FloatingState();
}

class _FloatingState extends State<_Floating>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a;

  @override
  void initState() {
    super.initState();
    _a = AnimationController(
      vsync: this,
      duration: AudioRoomController.chatTtl,
    );
    if (widget.animate) _a.forward();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) return widget.child;
    return AnimatedBuilder(
      animation: _a,
      builder: (_, child) {
        final v = _a.value;
        final opacity = v < 0.06
            ? v / 0.06
            : v > 0.8
                ? ((1 - v) / 0.2).clamp(0.0, 1.0)
                : 1.0;
        final dy = v < 0.06 ? (1 - v / 0.06) * 12 : 0.0;
        return Opacity(
          opacity: opacity,
          child: Transform.translate(offset: Offset(0, dy), child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// Caixinha de mensagem dentro da sala: emojis rápidos e campo de texto.
class AudioRoomComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final void Function(String text) onSend;
  final VoidCallback onClose;

  const AudioRoomComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onClose,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _border)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final e in audioRoomQuickEmojis)
              InkWell(
                onTap: () => onSend(e),
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(e, style: const TextStyle(fontSize: 24)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.grey.shade300),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 3,
                maxLength: AudioRoomController.chatMaxChars,
                textCapitalization: ChatComposerText.keyboardCapitalization,
                inputFormatters: [
                  ChatComposerText.leadingAlphaCapitalizationFormatter,
                ],
                textInputAction: TextInputAction.send,
                onSubmitted: onSend,
                decoration: InputDecoration(
                  hintText: t.get('audio_room_chat_type'),
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, v, __) {
              final ok = ChatComposerText.hasSendableText(v.text);
              return InkWell(
                onTap: ok ? () => onSend(v.text) : null,
                borderRadius: BorderRadius.circular(999),
                child: Opacity(
                  opacity: ok ? 1 : 0.5,
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
              );
            },
          ),
        ]),
      ]),
    );
  }
}
