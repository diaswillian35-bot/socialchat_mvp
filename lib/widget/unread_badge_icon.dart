import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UnreadBadgeIcon extends StatelessWidget {
  final IconData icon;
  final double size;

  const UnreadBadgeIcon({
    super.key,
    required this.icon,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Icon(icon, size: size);

    final q = FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: uid);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        int totalUnread = 0;

        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final data = d.data();
            final unreadMap = (data['unread'] is Map) ? (data['unread'] as Map) : {};
            final v = unreadMap[uid];
            if (v is int) totalUnread += v;
          }
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: size),
            if (totalUnread > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}