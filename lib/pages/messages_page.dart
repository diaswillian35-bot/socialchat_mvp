import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'chat_page.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  String get _myUid => FirebaseAuth.instance.currentUser!.uid;

  // ✅ Visual padrão Remdy (igual Home)
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    // ✅ IMPORTANTE:
    // Seu app antigo usa "participants" e "lastMessageAt".
    // (A bolinha vermelha no MainShell está usando members/unreadCount etc,
    // mas isso é separado e você pediu pra NÃO mexer nela.)
    final convQuery = db
        .collection('conversations')
        .where('participants', arrayContains: _myUid)
        .orderBy('lastMessageAt', descending: true);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Mensagens',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: _muted),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: convQuery.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}'));
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'Nenhuma conversa ainda.',
                style: TextStyle(fontWeight: FontWeight.w700, color: _muted),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final convDoc = docs[i];
              final data = convDoc.data();

              final participants =
                  (data['participants'] as List?)?.cast<String>() ?? [];

              final otherUid = participants.firstWhere(
                (u) => u != _myUid,
                orElse: () => '',
              );

              final lastMessage = (data['lastMessage'] ?? '').toString();

              // ✅ unread por usuário
              final unreadMap =
                  (data['unread'] is Map) ? Map<String, dynamic>.from(data['unread']) : {};
              final myUnread = (unreadMap[_myUid] is int) ? unreadMap[_myUid] as int : 0;

              // fallback
              final myUnread2 = (myUnread == 0 && data['unreadCount'] is Map)
                  ? ((data['unreadCount'][_myUid] is int) ? data['unreadCount'][_myUid] as int : 0)
                  : 0;

              final unreadFinal = myUnread > 0 ? myUnread : myUnread2;

              if (otherUid.isEmpty) {
                return _ConversationTile(
                  name: 'Usuário',
                  photoUrl: '',
                  subtitle: lastMessage,
                  unread: unreadFinal,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatPage(
                          conversationId: convDoc.id,
                          otherUid: otherUid,
                          otherName: 'Usuário',
                        ),
                      ),
                    );
                  },
                );
              }

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: db.collection('users').doc(otherUid).snapshots(),
                builder: (context, userSnap) {
                  final u = userSnap.data?.data() ?? {};
                  final name = (u['name'] ?? 'Usuário').toString();
                  final photoUrl = (u['photoUrl'] ?? '').toString();

                  return _ConversationTile(
                    name: name,
                    photoUrl: photoUrl,
                    subtitle: lastMessage,
                    unread: unreadFinal,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatPage(
                            conversationId: convDoc.id,
                            otherUid: otherUid,
                            otherName: name,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final String name;
  final String photoUrl;
  final String subtitle;
  final int unread;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.name,
    required this.photoUrl,
    required this.subtitle,
    required this.unread,
    required this.onTap,
  });

  static const Color _card = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    final hasUnread = unread > 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF1F5F9),
                image: photoUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(photoUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: photoUrl.isEmpty
                  ? const Icon(Icons.person, color: _muted)
                  : null,
            ),

            const SizedBox(width: 12),

            // Textos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: hasUnread ? FontWeight.w900 : FontWeight.w800,
                      fontSize: 15.5,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle.isNotEmpty ? subtitle : 'Toque para abrir',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasUnread ? _text : _muted,
                      fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 13.2,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Badge + chevron
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: _remdyBlue,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 24),
                const SizedBox(height: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: Color(0xFFCBD5E1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
