import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';


import 'chat_page.dart';
import 'public_profile_page.dart';
import '../widget/remdy_app.dart';


class LanguageUsersPage extends StatelessWidget {
  final String languageCode; // ex: 'BR', 'CA'
  final String languageName; // ex: 'Brasil'
  final String flag; // ex: '🇧🇷'


  const LanguageUsersPage({
    super.key,
    required this.languageCode,
    required this.languageName,
    required this.flag,
  });


  String get _myUid => FirebaseAuth.instance.currentUser!.uid;


  // ====== mantém a lógica de conversa (pairKey) ======
  String _pairKey(String a, String b) {
    final list = [a, b]..sort();
    return '${list[0]}_${list[1]}';
  }


  Future<String> _getOrCreateConversation(String otherUid) async {
    final db = FirebaseFirestore.instance;
    final key = _pairKey(_myUid, otherUid);
    final ref = db.collection('conversations').doc(key);


    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'participants': [_myUid, otherUid],
        'pairKey': key,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unread': {
          _myUid: 0,
          otherUid: 0,
        },
      }, SetOptions(merge: true));
    }
    return ref.id;
  }


  // ====== só visual (cores) ======
  static const Color _primary = Color(0xFF313A5F); // azul Remdy
  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _card = Colors.white;


  bool _isOnlineFromDoc(Map<String, dynamic> data) {
    final ts = data['lastSeenAt'];
    if (ts is! Timestamp) return false;


    final lastSeen = ts.toDate();
    // mantém a sua regra: < 2 min
    return DateTime.now().difference(lastSeen).inMinutes < 2;
  }


  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;


    // ✅ padroniza sempre em minúsculo
    final code = languageCode.trim().toLowerCase();


    // ✅ query estável: countryCode no Firestore é "ca", "br", etc
    final q = db.collection('users').where('countryCode', isEqualTo: code);


    return Scaffold(
      backgroundColor: _bg,


      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(languageName, style: const TextStyle(color: _text)),
        iconTheme: const IconThemeData(color: _muted),
      ),


      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}'));
          }


          final docs = snap.data?.docs ?? [];
          final filtered = docs.where((d) => d.id != _myUid).toList();


          if (filtered.isEmpty) {
            return const Center(child: Text('Nenhuma pessoa encontrada.'));
          }


          final onlineDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final offlineDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];


          for (final d in filtered) {
            final online = _isOnlineFromDoc(d.data());
            if (online) {
              onlineDocs.add(d);
            } else {
              offlineDocs.add(d);
            }
          }


          final children = <Widget>[];


          if (onlineDocs.isNotEmpty) {
            children.add(_SectionTitle(title: 'Online', count: onlineDocs.length));
            children.add(const SizedBox(height: 10));
            for (final d in onlineDocs) {
              children.add(_UserCard(
                doc: d,
                flag: flag,
                fallbackCountry: languageName,
                isOnline: true,
                onProfile: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PublicProfilePage(userUid: d.id)),
                  );
                },
                onChat: () async {
                  final data = d.data();
                  final otherUid = d.id;
                  final otherName = (data['name'] ?? 'Usuário').toString();


           String convoId = '';

try {
  convoId = await _getOrCreateConversation(otherUid);
} catch (e) {
  debugPrint('ERRO AO CRIAR CONVERSA: $e');

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erro ao abrir conversa: $e')),
    );
  }

  return;
}

if (!context.mounted) return;

Navigator.push(


                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        conversationId: convoId,
                        otherUid: otherUid,
                        otherName: otherName,
                      ),
                    ),
                  );
                },
              ));
              children.add(const SizedBox(height: 12));
            }
            children.add(const SizedBox(height: 10));
          }


          if (offlineDocs.isNotEmpty) {
            children.add(_SectionTitle(title: 'Offline', count: offlineDocs.length));
            children.add(const SizedBox(height: 10));
            for (final d in offlineDocs) {
              children.add(_UserCard(
                doc: d,
                flag: flag,
                fallbackCountry: languageName,
                isOnline: false,
                onProfile: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PublicProfilePage(userUid: d.id)),
                  );
                },
                onChat: () async {
                  final data = d.data();
                  final otherUid = d.id;
                  final otherName = (data['name'] ?? 'Usuário').toString();


                  final convoId = await _getOrCreateConversation(otherUid);
                  if (!context.mounted) return;


                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        conversationId: convoId,
                        otherUid: otherUid,
                        otherName: otherName,
                      ),
                    ),
                  );
                },
              ));
              children.add(const SizedBox(height: 12));
            }
          }


          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: children,
          );
        },
      ),
    );
  }
}


class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;
  const _SectionTitle({required this.title, required this.count});


  static const Color _text = Color(0xFF111827);


  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _text,
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ],
    );
  }
}


class _UserCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isOnline;
  final String flag;
  final String fallbackCountry;
  final VoidCallback onProfile;
  final VoidCallback onChat;


  const _UserCard({
    required this.doc,
    required this.isOnline,
    required this.flag,
    required this.fallbackCountry,
    required this.onProfile,
    required this.onChat,
  });


  static const Color _primary = Color(0xFF313A5F);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _card = Colors.white;


  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final name = (data['name'] ?? 'Sem nome').toString();
    final photoUrl = (data['photoUrl'] ?? '').toString();
    final country = (data['country'] ?? '').toString().trim();
    final countryLabel =
        country.isNotEmpty ? '$flag $country' : '$flag $fallbackCountry';


    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 54,
                  height: 54,
                  color: Colors.grey.shade200,
                  child: (photoUrl.isNotEmpty)
                      ? Image.network(photoUrl, fit: BoxFit.cover)
                      : const Icon(Icons.person, size: 26),
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
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusDot(online: isOnline),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            countryLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),


          const SizedBox(height: 10),


          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onProfile,
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: const Text(
                    'Perfil',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text(
                    'Conversar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class _StatusDot extends StatelessWidget {
  final bool online;
  const _StatusDot({required this.online});


  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: online ? Colors.green : const Color(0xFF9CA3AF),
        shape: BoxShape.circle,
      ),
    );
  }
}
