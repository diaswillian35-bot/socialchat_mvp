import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';


class OnlineDot extends StatelessWidget {
  final String uid;
  final double size;
  final bool showBorder;
  final int onlineSeconds;


  const OnlineDot({
    super.key,
    required this.uid,
    this.size = 10,
    this.showBorder = true,
    this.onlineSeconds = 35,
  });


  DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is int) {
      if (v < 2000000000) {
        return DateTime.fromMillisecondsSinceEpoch(v * 1000);
      }
      return DateTime.fromMillisecondsSinceEpoch(v);
    }
    if (v is num) {
      final n = v.toInt();
      if (n < 2000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n * 1000);
      }
      return DateTime.fromMillisecondsSinceEpoch(n);
    }
    if (v is String) return DateTime.tryParse(v);
    return null;
  }


  bool _isOnlineFrom(Map<String, dynamic> data) {
    final lastSeen = _toDateTime(data['lastSeenAt']);
    if (lastSeen == null) return false;


    final diff = DateTime.now().difference(lastSeen).inSeconds;
    return diff <= onlineSeconds;
  }


  @override
  Widget build(BuildContext context) {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);


    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final isOnline = _isOnlineFrom(data);


        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isOnline ? Colors.green : const Color(0xFFCBD5E1),
            shape: BoxShape.circle,
            border: showBorder
                ? Border.all(color: Colors.white, width: 2)
                : null,
          ),
        );
      },
    );
  }
}


class AvatarWithOnlineDot extends StatelessWidget {
  final Widget avatar;
  final String uid;
  final double dotSize;
  final int onlineSeconds;


  const AvatarWithOnlineDot({
    super.key,
    required this.avatar,
    required this.uid,
    this.dotSize = 10,
    this.onlineSeconds = 35,
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
          child: OnlineDot(
            uid: uid,
            size: dotSize,
            onlineSeconds: onlineSeconds,
          ),
        ),
      ],
    );
  }
}
