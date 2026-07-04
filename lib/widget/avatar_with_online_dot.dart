import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';


class AvatarWithOnlineDot extends StatelessWidget {
  final String uid;
  final String photoUrl;


  /// raio do avatar (26 = 52x52)
  final double radius;


  /// tamanho do ponto verde
  final double dotSize;


  /// tolerância em segundos para considerar ONLINE
  final int onlineSeconds;


  const AvatarWithOnlineDot({
    super.key,
    required this.uid,
    required this.photoUrl,
    this.radius = 26,
    this.dotSize = 12,
    this.onlineSeconds = 90,
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


    if (v is String) {
      return DateTime.tryParse(v);
    }


    return null;
  }


  bool _isOnlineFrom(Map<String, dynamic> data) {
    // ✅ timestamp é a fonte de verdade
    final lastSeen = _toDateTime(data['lastSeenAt']);
    final updated = _toDateTime(data['updatedAt']);


    final now = DateTime.now();


    bool recent(DateTime? dt) {
      if (dt == null) return false;
      final diff = now.difference(dt).inSeconds;
      return diff >= 0 && diff <= onlineSeconds;
    }


    // ✅ ONLINE só se tiver ping recente
    final byTime = recent(lastSeen) || recent(updated);
    if (byTime) return true;


    // ✅ compat: só usa isOnline se NÃO EXISTIR timestamp nenhum
    // (isso evita ficar verde pra sempre quando isOnline ficou travado true)
    final hasAnyTime = (lastSeen != null) || (updated != null);
    if (hasAnyTime) return false;


    final boolFlag = data['isOnline'];
    return (boolFlag is bool) ? boolFlag : false;
  }


  @override
  Widget build(BuildContext context) {
    if (uid.trim().isEmpty) {
      return _AvatarOnly(photoUrl: photoUrl, radius: radius);
    }


    final db = FirebaseFirestore.instance;


    // prioridade: publicUsers (onde PresenceService atualiza)
    final pubStream = db.collection('publicUsers').doc(uid).snapshots();


    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: pubStream,
      builder: (context, snap) {
        if (snap.hasData && (snap.data?.exists ?? false)) {
          final data = snap.data?.data() ?? {};
          final online = _isOnlineFrom(data);


          return Stack(
            clipBehavior: Clip.none,
            children: [
              _AvatarOnly(photoUrl: photoUrl, radius: radius),
              if (online) _OnlineDot(dotSize: dotSize),
            ],
          );
        }


        // fallback: users/{uid}
        final userStream = db.collection('users').doc(uid).snapshots();


        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userStream,
          builder: (context, s2) {
            final data = (s2.hasData && (s2.data?.exists ?? false))
                ? (s2.data?.data() ?? {})
                : <String, dynamic>{};


            final online = _isOnlineFrom(data);


            return Stack(
              clipBehavior: Clip.none,
              children: [
                _AvatarOnly(photoUrl: photoUrl, radius: radius),
                if (online) _OnlineDot(dotSize: dotSize),
              ],
            );
          },
        );
      },
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


class _OnlineDot extends StatelessWidget {
  final double dotSize;


  const _OnlineDot({
    required this.dotSize,
  });


  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: -1,
      bottom: -1,
      child: Container(
        width: dotSize,
        height: dotSize,
        decoration: BoxDecoration(
          color: const Color(0xFF22C55E),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
      ),
    );
  }
}
