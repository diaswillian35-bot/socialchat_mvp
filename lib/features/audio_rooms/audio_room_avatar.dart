import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/user_avatar_resolver.dart';

const Color _remdyBlue = Color(0xFF313A5F);

/// Foto pública (publicUsers) com inicial de fallback; cache em memória.
class AudioRoomAvatar extends StatelessWidget {
  final String uid;
  final String name;
  final double radius;

  /// Anel verde (mesmo verde do microfone ligado) enquanto a pessoa fala.
  final bool speaking;

  const AudioRoomAvatar({
    super.key,
    required this.uid,
    this.name = '',
    this.radius = 20,
    this.speaking = false,
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
    // O anel fica por fora da foto, sem mudar o tamanho da linha.
    return Stack(clipBehavior: Clip.none, children: [
      _avatar(),
      Positioned(
        left: -3,
        top: -3,
        right: -3,
        bottom: -3,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: speaking ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.green, width: 2.5),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _avatar() {
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: _remdyBlue,
      child: name.trim().isEmpty
          ? Icon(Icons.person_rounded, color: Colors.white, size: radius)
          : Text(
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
