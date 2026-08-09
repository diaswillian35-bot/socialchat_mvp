import 'package:flutter/material.dart';

import '../services/presence_rtdb_config.dart';
import '../services/presence_watch.dart';

/// Bolinha de grupo: verde se qualquer membro observado estiver online (RTDB).
///
/// Usa [PresenceWatch.watchOnlineCount] → hub compartilhado por UID.
/// Não lê Firestore `isOnline` / `lastSeenAt`.
class GroupOnlineDot extends StatelessWidget {
  final List<String> memberIds;
  final bool enabled;
  final double size;

  const GroupOnlineDot({
    super.key,
    required this.memberIds,
    this.enabled = true,
    this.size = 10,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return _dot(const Color(0xFFCBD5E1));
    }
    final uids = memberIds.map((e) => e.trim()).where((e) => e.isNotEmpty);
    return StreamBuilder<int>(
      stream: PresenceWatch.watchOnlineCount(
        uids: uids,
        maxWatches: PresenceRtdbConfig.maxGroupPresenceWatches,
      ),
      initialData: 0,
      builder: (context, snap) {
        final n = snap.data ?? 0;
        return _dot(n > 0 ? const Color(0xFF22C55E) : const Color(0xFFCBD5E1));
      },
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}
