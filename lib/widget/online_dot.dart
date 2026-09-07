import 'package:flutter/material.dart';

import '../services/presence_session_state.dart';
import '../services/presence_watch.dart';

/// Bolinha de presença — RTDB via hub tri-estado.
///
/// Verde = online confirmado · Cinza = offline confirmado ·
/// Neutro = unavailable/carregando (nunca cinza por erro).
class OnlineDot extends StatelessWidget {
  final String uid;
  final double size;
  final bool showBorder;

  const OnlineDot({
    super.key,
    required this.uid,
    this.size = 10,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    if (uid.trim().isEmpty) {
      return _dot(PresenceReadStatus.offline);
    }

    return StreamBuilder<PresenceReadStatus>(
      stream: PresenceWatch.watchStatus(uid),
      builder: (context, snap) {
        final status = snap.data ?? PresenceReadStatus.unavailable;
        return _dot(status);
      },
    );
  }

  Widget _dot(PresenceReadStatus status) {
    final Color color;
    switch (status) {
      case PresenceReadStatus.online:
        color = Colors.green;
        break;
      case PresenceReadStatus.offline:
        color = const Color(0xFFCBD5E1);
        break;
      case PresenceReadStatus.unavailable:
        color = const Color(0xFFE5E7EB);
        break;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: showBorder ? Border.all(color: Colors.white, width: 2) : null,
      ),
    );
  }
}

class AvatarWithOnlineDot extends StatelessWidget {
  final Widget avatar;
  final String uid;
  final double dotSize;

  const AvatarWithOnlineDot({
    super.key,
    required this.avatar,
    required this.uid,
    this.dotSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: OnlineDot(uid: uid, size: dotSize),
        ),
      ],
    );
  }
}
