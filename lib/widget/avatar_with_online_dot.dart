import 'package:flutter/material.dart';

import 'online_dot.dart' as unified;

/// Avatar + bolinha — delega presença ao [OnlineDot] (Realtime Database).
class AvatarWithOnlineDot extends StatelessWidget {
  final String uid;
  final String photoUrl;
  final double radius;
  final double dotSize;

  /// Ignorado — presença vem do RTDB, não de lastSeenAt Firestore.
  final int onlineSeconds;

  const AvatarWithOnlineDot({
    super.key,
    required this.uid,
    required this.photoUrl,
    this.radius = 26,
    this.dotSize = 12,
    this.onlineSeconds = 90,
  });

  @override
  Widget build(BuildContext context) {
    return unified.AvatarWithOnlineDot(
      uid: uid,
      dotSize: dotSize,
      avatar: _AvatarOnly(photoUrl: photoUrl, radius: radius),
    );
  }
}

class _AvatarOnly extends StatelessWidget {
  final String photoUrl;
  final double radius;

  const _AvatarOnly({
    required this.photoUrl,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF1F5F9),
        image: photoUrl.trim().isNotEmpty
            ? DecorationImage(
                image: NetworkImage(photoUrl),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: photoUrl.trim().isEmpty
          ? const Icon(Icons.person, color: Color(0xFF6B7280))
          : null,
    );
  }
}
