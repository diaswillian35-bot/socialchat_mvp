import 'package:flutter/material.dart';

/// Time + optional discrete send/read status under a chat bubble.
class MessageStatusFooter extends StatelessWidget {
  const MessageStatusFooter({
    super.key,
    required this.timeText,
    this.statusText,
    required this.isMe,
  });

  final String timeText;
  final String? statusText;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    if (timeText.isEmpty && (statusText == null || statusText!.isEmpty)) {
      return const SizedBox.shrink();
    }
    final color = isMe ? Colors.white70 : const Color(0xFF6B7280);
    final style = TextStyle(
      color: color,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    final label = (statusText != null && statusText!.isNotEmpty)
        ? (timeText.isEmpty ? statusText! : '$timeText · $statusText')
        : timeText;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(label, style: style),
    );
  }
}
