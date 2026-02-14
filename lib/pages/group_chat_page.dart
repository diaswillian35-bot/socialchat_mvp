import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class GroupChatPage extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupChatPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final db = FirebaseFirestore.instance;

  final _textC = TextEditingController();
  final _scrollC = ScrollController();

  String? get myUidOrNull => FirebaseAuth.instance.currentUser?.uid;

  bool _sending = false;
  DateTime? _lastSentAt;
  static const int _cooldownMs = 700;

  int _lastMsgCount = 0;

  // Visual padrão Remdy
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  DocumentReference<Map<String, dynamic>> get groupDoc =>
      db.collection('groups').doc(widget.groupId);

  CollectionReference<Map<String, dynamic>> get msgsCol =>
      groupDoc.collection('messages');

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _msgsStream;

  void _warn(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _containsLink(String text) {
    final t = text.toLowerCase();
    return t.contains('http://') ||
        t.contains('https://') ||
        t.contains('www.') ||
        t.contains('.com') ||
        t.contains('.net') ||
        t.contains('.ca') ||
        t.contains('.br');
  }

  bool _containsPhone(String text) {
    final t = text.trim();
    final intl = RegExp(r'\+\s?\d{1,3}');
    final generic = RegExp(r'\d[\d\s().-]{7,}\d');
    return intl.hasMatch(t) || generic.hasMatch(t);
  }

  Future<void> _send() async {
    if (_sending) return;

    final uid = myUidOrNull;
    if (uid == null) {
      _warn('Você precisa estar logado.');
      return;
    }

    final now = DateTime.now();
    if (_lastSentAt != null) {
      final diff = now.difference(_lastSentAt!).inMilliseconds;
      if (diff < _cooldownMs) return;
    }

    final text = _textC.text.trim();
    if (text.isEmpty) return;

    if (_containsLink(text)) {
      _warn('Links não são permitidos no chat.');
      return;
    }

    if (_containsPhone(text)) {
      _warn('Por segurança, não é permitido enviar número de telefone.');
      return;
    }

    _sending = true;
    _lastSentAt = now;
    _textC.clear();

    try {
      await msgsCol.add({
        'text': text,
        'senderId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await groupDoc.set({
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // com reverse:true, o topo é 0
      Future.delayed(const Duration(milliseconds: 80), () {
        if (!_scrollC.hasClients) return;
        _scrollC.jumpTo(0);
      });
    } catch (e) {
      _warn('Erro ao enviar: $e');
    } finally {
      _sending = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _msgsStream = msgsCol.orderBy('createdAt', descending: true).snapshots();
  }

  @override
  void dispose() {
    _textC.dispose();
    _scrollC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = myUidOrNull;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        titleSpacing: 0,
        iconTheme: const IconThemeData(color: _muted),
        title: Text(
          widget.groupName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: const Color(0xFFF8FAFC),
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _msgsStream,
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

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!_scrollC.hasClients) return;
                    if (docs.length != _lastMsgCount) {
                      _lastMsgCount = docs.length;
                      _scrollC.jumpTo(0);
                    }
                  });

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
                        enabled: uid != null, // ✅ não quebra se deslogar
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

  const _Bubble({
    required this.text,
    required this.isMe,
  });

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
