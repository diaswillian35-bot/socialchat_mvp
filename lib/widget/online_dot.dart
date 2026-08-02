import 'package:flutter/material.dart';

import '../services/presence_watch.dart';

/// Bolinha de presença — somente Realtime Database (`presence/{uid}/connections`).
///
/// Listener ativo só enquanto o widget estiver montado.
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
    if (uid.trim().isEmpty) return _dot(false);

    return StreamBuilder<bool>(
      stream: PresenceWatch.watchIsOnline(uid),
      initialData: false,
      builder: (context, snap) => _dot(snap.data == true),
    );
  }

  Widget _dot(bool isOnline) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isOnline ? Colors.green : const Color(0xFFCBD5E1),
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
