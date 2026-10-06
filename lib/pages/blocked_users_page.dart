import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/block_service.dart';
import '../services/blocked_users_list_logic.dart';
import '../services/user_avatar_resolver.dart';

/// Reachable list of `users/{me}.blocked` so a hidden user can still be unblocked.
class BlockedUsersPage extends StatelessWidget {
  const BlockedUsersPage({super.key});

  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final uid = _uid;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          t.get('blocked_users_title'),
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: uid == null
          ? Center(child: Text(t.get('blocked_users_empty')))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final ids = BlockedUsersListLogic.orderedUids(
                  snap.data?.data()?['blocked'],
                );
                if (ids.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        t.get('blocked_users_empty'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: ids.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _BlockedUserTile(uid: ids[index]);
                  },
                );
              },
            ),
    );
  }
}

class _BlockedUserTile extends StatelessWidget {
  const _BlockedUserTile({required this.uid});

  final String uid;

  Future<void> _unblock(BuildContext context) async {
    final t = AppTexts.current;
    try {
      await BlockService.unblockUser(uid);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.get('blocked_users_unblocked'))),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('publicUsers')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final name = BlockedUsersListLogic.labelFromPublic(data, uid);
        final photo = UserAvatarResolver.resolve(data);
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFEEF2FF),
            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo.isEmpty
                ? Text(
                    UserAvatarResolver.initialFor(name),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  )
                : null,
          ),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          trailing: TextButton(
            onPressed: () => _unblock(context),
            child: Text(t.get('blocked_users_unblock')),
          ),
        );
      },
    );
  }
}
