import 'package:flutter/material.dart';

import '../../l10n/app_texts.dart';
import 'audio_room_avatar.dart';
import 'audio_room_controller.dart';
import 'audio_room_service.dart';

const Color _text = Color(0xFF111827);
const Color _muted = Color(0xFF6B7280);
const Color _border = Color(0xFFE5E7EB);
const Color _remdyBlue = Color(0xFF313A5F);

/// Card "Ao vivo" no topo do grupo enquanto a sala estiver aberta.
class GroupLiveCard extends StatelessWidget {
  final String groupId;
  final VoidCallback onEnter;

  const GroupLiveCard(
      {super.key, required this.groupId, required this.onEnter});

  @override
  Widget build(BuildContext context) {
    final c = AudioRoomController.instance;
    return StreamBuilder<AudioRoomInfo?>(
      stream: c.service.liveRoom(groupId),
      builder: (context, snap) {
        final room = snap.data;
        if (room == null) return const SizedBox.shrink();
        return AnimatedBuilder(
          animation: c,
          builder: (context, _) => GroupLiveCardView(
            room: room,
            inside: c.isInGroup(groupId),
            enabled: !c.connecting,
            onEnter: onEnter,
          ),
        );
      },
    );
  }
}

/// Parte visual do card, sem Firebase (usada também nos prints).
class GroupLiveCardView extends StatelessWidget {
  final AudioRoomInfo room;
  final bool inside;
  final bool enabled;
  final VoidCallback onEnter;

  const GroupLiveCardView({
    super.key,
    required this.room,
    required this.inside,
    required this.enabled,
    required this.onEnter,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final uids = room.presentUids.take(3).toList();
    final subtitle = room.openedByName.isNotEmpty
        ? t.get('audio_room_opened_by').replaceAll('{name}', room.openedByName)
        : t
            .get('audio_room_participants')
            .replaceAll('{count}', '${room.participantCount}');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        const Icon(Icons.headset_mic_rounded, color: _remdyBlue, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.circle, size: 8, color: Colors.red),
                const SizedBox(width: 6),
                Text(t.get('audio_room_live'),
                    style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ]),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ],
          ),
        ),
        if (uids.isNotEmpty)
          SizedBox(
            width: 14.0 * uids.length + 14,
            height: 28,
            child: Stack(children: [
              for (var i = 0; i < uids.length; i++)
                Positioned(
                  left: 14.0 * i,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: AudioRoomAvatar(uid: uids[i], radius: 12),
                  ),
                ),
            ]),
          ),
        const SizedBox(width: 6),
        TextButton(
          onPressed: enabled ? onEnter : null,
          child: Text(
            inside ? t.get('audio_room_back') : t.get('audio_room_join'),
            style:
                const TextStyle(color: _remdyBlue, fontWeight: FontWeight.w800),
          ),
        ),
      ]),
    );
  }
}
