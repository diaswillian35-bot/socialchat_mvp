import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'explore_only.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';

/// b44: "Bloquear mensagens privadas".
///
/// users/{uid}.dmBlocked (bool) + dmAllowExisting (bool), espelhados em
/// publicUsers/{uid} para os outros mostrarem o cadeado. O bloqueio real fica
/// nas regras do Firestore e nas callables (sendDmMessage, forwardMessage,
/// sendShareMessage), nos dois sentidos; o cliente só avisa antes.
class DmBlock {
  DmBlock._();

  static const String field = 'dmBlocked';
  static const String allowExistingField = 'dmAllowExisting';

  static bool isBlockedData(Map<String, dynamic>? data) =>
      data != null && data[field] == true;

  /// true se [data] (da outra pessoa) impede mandar PV nesta conversa.
  static bool blocksSend(Map<String, dynamic>? data,
      {required bool hasHistory}) {
    if (!isBlockedData(data)) return false;
    if (data![allowExistingField] == true && hasHistory) return false;
    return true;
  }

  static Future<void> save(String uid,
      {required bool blocked, required bool allowExisting}) async {
    final db = FirebaseFirestore.instance;
    final patch = {
      field: blocked,
      allowExistingField: allowExisting,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await db.collection('users').doc(uid).set(patch, SetOptions(merge: true));
    await db
        .collection('publicUsers')
        .doc(uid)
        .set(patch, SetOptions(merge: true));
  }

  /// Mesmo padrão de ExploreOnly.blocksNewChat (conversa nova): SnackBar e
  /// true se a outra pessoa ou eu bloqueamos PV. Lê users/ (fonte das regras).
  static Future<bool> blocksNewChat(
      BuildContext context, String otherUid) async {
    if (otherUid.trim().isEmpty) return false;
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    var selfBlocked = false;
    try {
      final db = FirebaseFirestore.instance;
      final other = await db.collection('users').doc(otherUid).get();
      if (isBlockedData(other.data())) {
        if (context.mounted) showNotice(context);
        return true;
      }
      if (me.isNotEmpty) {
        final mine = await db.collection('users').doc(me).get();
        selfBlocked = isBlockedData(mine.data());
      }
    } catch (_) {
      return false;
    }
    if (!selfBlocked) return false;
    if (context.mounted) showNotice(context, key: 'dm_blocked_self_hint');
    return true;
  }

  /// Explorar-só (ExploreOnly) ou PV bloqueado: um único ponto para os 4
  /// lugares que abrem conversa nova.
  static Future<bool> blocksNewChatAny(
      BuildContext context, String otherUid) async {
    if (await ExploreOnly.blocksNewChat(context, otherUid)) return true;
    if (!context.mounted) return false;
    return blocksNewChat(context, otherUid);
  }

  /// Erros das callables (details.reason) que viram aviso próprio.
  static String? errorNoticeKey(String? code) {
    switch (code) {
      case 'dm-blocked':
        return 'dm_blocked_no_chat';
      case 'muted':
        return 'mod_muted_send_blocked';
      case 'insult':
      case 'insult_blocked':
        return 'insult_blocked_notice';
      default:
        return null;
    }
  }

  static void showNotice(BuildContext context,
      {String key = 'dm_blocked_no_chat'}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AppTexts.current.get(key))),
      );
  }
}

/// Cadeado ao lado do nome/foto quando a pessoa bloqueou PV.
class DmLockMark extends StatelessWidget {
  const DmLockMark({
    super.key,
    required this.uid,
    this.icon = Icons.lock_rounded,
    this.size = 12,
    this.color = const Color(0xFF6B7280),
    this.gap = 6,
  });

  final String uid;
  final IconData icon;
  final double size;
  final Color color;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (uid.trim().isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('publicUsers')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        if (!DmBlock.isBlockedData(snap.data?.data())) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: EdgeInsets.only(left: gap),
          child: Icon(
            icon,
            size: size,
            color: color,
            semanticLabel: AppTexts.current.get('dm_lock_a11y'),
          ),
        );
      },
    );
  }
}

/// b44: selo de verificado (publicUsers.verified, só gravável pelo
/// servidor) + cadeado de PV, lado a lado do nome.
class ProfileMarks extends StatelessWidget {
  const ProfileMarks({super.key, required this.uid, this.size = 14, this.data});

  final String uid;
  final double size;

  /// Dados já carregados (publicUsers/{uid}); evita outro listener.
  final Map<String, dynamic>? data;

  static const Color _brand = Color(0xFF313A5F);
  static const Color _muted = Color(0xFF6B7280);

  static bool isVerifiedData(Map<String, dynamic>? d) =>
      d != null && d['verified'] == true;

  @override
  Widget build(BuildContext context) {
    if (data != null) return _marks(data);
    if (uid.trim().isEmpty || Firebase.apps.isEmpty) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('publicUsers')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) => _marks(snap.data?.data()),
    );
  }

  Widget _marks(Map<String, dynamic>? d) {
    final verified = isVerifiedData(d);
    final locked = DmBlock.isBlockedData(d);
    if (!verified && !locked) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (verified) ...[
        const SizedBox(width: 6),
        Icon(Icons.verified,
            size: size,
            color: _brand,
            semanticLabel: AppTexts.current.get('verified_badge_a11y')),
      ],
      if (locked) ...[
        const SizedBox(width: 6),
        Icon(Icons.lock_rounded,
            size: size,
            color: _muted,
            semanticLabel: AppTexts.current.get('dm_lock_a11y')),
      ],
    ]);
  }
}

/// b44: "sem falar" por moderação (users/{uid}.moderation.mutedUntil,
/// só gravável pelo servidor). Regras/functions impõem; o cliente só avisa.
class ModerationMute {
  ModerationMute._();

  static DateTime? until(Map<String, dynamic>? data, {DateTime? now}) {
    final m = data?['moderation'];
    if (m is! Map) return null;
    final raw = m['mutedUntil'];
    final DateTime? t = raw is Timestamp
        ? raw.toDate()
        : raw is DateTime
            ? raw
            : null;
    if (t == null) return null;
    return t.isAfter(now ?? DateTime.now()) ? t : null;
  }

  static String format(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}, ${two(t.hour)}:${two(t.minute)}';
  }
}
