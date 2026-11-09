import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/user_avatar_resolver.dart';

const Color _remdyBlue = Color(0xFF313A5F);

/// Foto pública (publicUsers) com inicial de fallback; cache em memória.
class AudioRoomAvatar extends StatelessWidget {
  final String uid;
  final String name;
  final double radius;

  const AudioRoomAvatar({
    super.key,
    required this.uid,
    this.name = '',
    this.radius = 20,
  });

  static final Map<String, Future<String>> _cache = {};

  static Future<String> _photo(String uid) => _cache.putIfAbsent(uid, () async {
        try {
          final s = await FirebaseFirestore.instance
              .collection('publicUsers')
              .doc(uid)
              .get();
          return UserAvatarResolver.resolve(s.data());
        } catch (_) {
          return '';
        }
      });

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: _remdyBlue,
      child: Text(
        UserAvatarResolver.initialFor(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.75,
        ),
      ),
    );
    if (uid.isEmpty) return fallback;
    return FutureBuilder<String>(
      future: _photo(uid),
      builder: (context, snap) {
        final url = snap.data ?? '';
        if (url.isEmpty) return fallback;
        return CircleAvatar(
          radius: radius,
          backgroundColor: _remdyBlue,
          backgroundImage: NetworkImage(url),
        );
      },
    );
  }
}
