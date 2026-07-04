import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PrivateChatPage extends StatefulWidget {
  final String otherUid;

  const PrivateChatPage({
    super.key,
    required this.otherUid,
  });

  @override
  State<PrivateChatPage> createState() => _PrivateChatPageState();
}

class _PrivateChatPageState extends State<PrivateChatPage> {
  final db = FirebaseFirestore.instance;

  final _textC = TextEditingController();
  final _scrollC = ScrollController();

  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _remdyBlue = Color(0xFF313A5F);

  String? _conversationId;
  bool _loading = true;

  String? get myUid => FirebaseAuth.instance.currentUser?.uid;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  String _pairId(String a, String b) {
    final x = a.compareTo(b) <= 0 ? a : b;
    final y = a.compareTo(b) <= 0 ? b : a;
    return '${x}_$y';
  }

  Future<void> _ensureConversation() async {
    final uid = myUid;
    if (uid == null) {
      _toast('Faça login para conversar.');
      setState(() => _loading = false);
      return;
    }
    if (uid == widget.otherUid) {
      _toast('Você não pode conversar com você mesmo.');
      setState(() => _loading = false);
      return;
    }

    try {
      final pairId = _pairId(uid, widget.otherUid);

      final q = await db
          .collection('conversations')
          .where('pairId', isEqualTo: pairId)
          .limit(1)
          .get();

      if (q.docs.isNotEmpty) {
        _conversationId = q.docs.first.id;
      } else {
        final doc = await db.collection('conversations').add({
          'type': 'dm',
          'pairId': pairId,
          'participants': [uid, widget.otherUid],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
        });
        _conversationId = doc.id;
      }
    } catch (e) {
      _toast('Erro criando conversa: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  CollectionReference<Map<String, dynamic>> get _msgsCol =>
      db.collection('conversations').doc(_conversationId).collection('messages');

  Future<void> _send() async {
    final uid = myUid;
    if (uid == null) return _toast('Faça login.');
    final cid = _conversationId;
    if (cid == null) return;

    final text = _textC.text.trim();
    if (text.isEmpty) return;

    _textC.clear();

    try {
      await _msgsCol.add({
        'text': text,
        'senderId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await db.collection('conversations').doc(cid).set({
        'lastMessage': text,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      Future.delayed(const Duration(milliseconds: 80), () {
        if (!_scrollC.hasClients) return;
        _scrollC.jumpTo(0);
      });
    } catch (e) {
      _toast('Erro ao enviar: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _ensureConversation();
  }

  @override
  void dispose() {
    _textC.dispose();
    _scrollC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = myUid;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _text,
        iconTheme: const IconThemeData(color: _muted),
        centerTitle: true,
        title: const Text(
          'Chat privado',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_conversationId == null)
              ? const Center(child: Text('Não foi possível abrir o chat.'))
              : Column(
                  children: [
                    Expanded(
                      child: Container(
                        color: const Color(0xFFF8FAFC),
                        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _msgsCol
                              .orderBy('createdAt', descending: true)
                              .snapshots(),
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
                                  'Nenhuma mensagem ainda.',
                                  style: TextStyle(
                                    color: _muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }

                            return ListView.builder(
                              controller: _scrollC,
                              reverse: true,
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                              itemCount: docs.length,
                              itemBuilder: (context, i) {
                                final d = docs[i].data();
                                final text = (d['text'] ?? '').toString();
                                final senderId = (d['senderId'] ?? '').toString();
                                final isMe = (uid != null && senderId == uid);
                                return _Bubble(text: text, isMe: isMe);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(top: BorderSide(color: Colors.grey.shade300)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                child: TextField(
                                  controller: _textC,
                                  enabled: uid != null,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send(),
                                  decoration: InputDecoration(
                                    hintText: uid == null
                                        ? 'Faça login para conversar...'
                                        : 'Digite uma mensagem...',
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: uid == null ? null : _send,
                              borderRadius: BorderRadius.circular(999),
                              child: Opacity(
                                opacity: uid == null ? 0.5 : 1,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _remdyBlue,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Icon(Icons.send, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool isMe;

  const _Bubble({required this.text, required this.isMe});

  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? _remdyBlue : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMe ? _remdyBlue : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isMe ? Colors.white : const Color(0xFF111827),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
