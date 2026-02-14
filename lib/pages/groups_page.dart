import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'group_chat_page.dart';

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  final db = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      db.collection('users').doc(uid);

  // Visual padrão Remdy (igual suas páginas)
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// ✅ Entra no grupo sem duplicar contagem:
  /// - se o uid já estiver em members, NÃO incrementa
  /// - se não estiver, adiciona e incrementa membersCount
  Future<void> _joinAndOpen({
    required String groupId,
    required String groupName,
  }) async {
    final uid = _uid;
    if (uid == null) {
      _toast('Você precisa estar logado.');
      return;
    }

    final ref = db.collection('groups').doc(groupId);

    try {
      await db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data() as Map<String, dynamic>? ?? {};

        final membersRaw = (data['members'] is List) ? (data['members'] as List) : [];
        final members = membersRaw.map((e) => e.toString()).toList();

        final already = members.contains(uid);

        if (!already) {
          tx.set(ref, {
            'members': FieldValue.arrayUnion([uid]),
            'membersCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          // só atualiza updatedAt (opcional)
          tx.set(ref, {
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      });

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupChatPage(
            groupId: groupId,
            groupName: groupName,
          ),
        ),
      );
    } catch (e) {
      _toast('Erro ao entrar no grupo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Precisa estar logado.')),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text(
          'Grupos',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: _muted),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userDoc(uid).snapshots(),
        builder: (context, userSnap) {
          final u = userSnap.data?.data() ?? {};
          final bool isPremium = u['isPremium'] == true;
          final String myCountryCode =
              (u['countryCode'] ?? 'ca').toString().trim().toLowerCase();

          final groupsStream = db
              .collection('groups')
              .orderBy('createdAt', descending: true)
              .snapshots();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: groupsStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Erro: ${snap.error}'));
              }

              final docs = snap.data?.docs ?? [];

              // ✅ Filtro: mundo só premium, país só do país
              final visible = docs.where((d) {
                final data = d.data();
                final scope = (data['scope'] ?? 'country').toString().toLowerCase();

                if (scope == 'world') {
                  return isPremium;
                }

                final code = (data['countryCode'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();

                return code.isNotEmpty && code == myCountryCode;
              }).toList();

              if (visible.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: _border),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      isPremium
                          ? 'Nenhum grupo disponível ainda.'
                          : 'Nenhum grupo do seu país ainda.',
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final doc = visible[i];
                  final data = doc.data();

                  final groupId = doc.id;
                  final name = (data['name'] ?? 'Grupo').toString();
                  final scope = (data['scope'] ?? 'country').toString().toLowerCase();
                  final countryCode =
                      (data['countryCode'] ?? '').toString().toUpperCase();

                  final membersCount = (data['membersCount'] is int)
                      ? data['membersCount'] as int
                      : 0;

                  final subtitle = scope == 'world'
                      ? 'Mundo • Premium'
                      : 'País: $countryCode • $membersCount membros';

                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _joinAndOpen(
                      groupId: groupId,
                      groupName: name,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
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
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              scope == 'world' ? Icons.public : Icons.flag,
                              color: _remdyBlue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFFCBD5E1),
                          ),
                        ],
                      ),
                    ),
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
