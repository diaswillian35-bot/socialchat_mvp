import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


import 'group_info_page.dart';


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
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _remdyBlue = Color(0xFF313A5F);


  final _textC = TextEditingController();
  final _scrollC = ScrollController();


  String? get uid => FirebaseAuth.instance.currentUser?.uid;


  DocumentReference<Map<String, dynamic>> get _groupRef =>
      FirebaseFirestore.instance.collection('groups').doc(widget.groupId);


  CollectionReference<Map<String, dynamic>> get _msgsRef =>
      _groupRef.collection('messages');


  bool _isAdmin = false;
  bool _loadingRole = true;


  @override
  void initState() {
    super.initState();


    _loadMyRole();


    // ✅ zera unread ao entrar (depois do build)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _markGroupAsRead();
    });
  }


  @override
  void dispose() {
    _textC.dispose();
    _scrollC.dispose();
    super.dispose();
  }


  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
      ),
    );
  }


  Future<void> _loadMyRole() async {
    final myUid = uid;
    if (myUid == null) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
        _loadingRole = false;
      });
      return;
    }


    try {
      final g = await _groupRef.get();
      final gd = g.data() ?? {};


      final ownerId = (gd['ownerId'] ?? '').toString();
      final adminsRaw = gd['admins'];


      final admins = (adminsRaw is List)
          ? adminsRaw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
          : <String>[];


      final isAdmin = (myUid == ownerId) || admins.contains(myUid);


      if (!mounted) return;
      setState(() {
        _isAdmin = isAdmin;
        _loadingRole = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
        _loadingRole = false;
      });
    }
  }


  // ✅ Marca leitura (unread.{uid} = 0) + mantém reads
  Future<void> _markGroupAsRead() async {
    final myUid = uid;
    if (myUid == null) return;


    // mantém reads
    await _groupRef.collection('reads').doc(myUid).set({
      'lastReadAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));


    // zera unread pro usuário
    try {
      await _groupRef.update({'unread.$myUid': 0});
    } catch (_) {
      await _groupRef.set({
        'unread': {myUid: 0}
      }, SetOptions(merge: true));
    }
  }


  Future<void> _send() async {
    final myUid = uid;
    if (myUid == null) return;


    final text = _textC.text.trim();
    if (text.isEmpty) return;


    _textC.clear();


    try {
      // ✅ Lê membros antes (pra montar patch)
      final g = await _groupRef.get();
      final gd = g.data() ?? {};
      final membersRaw = gd['members'];


      final members = (membersRaw is List)
          ? membersRaw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
          : <String>[];


      // ✅ Batch: grava msg + atualiza doc do grupo + atualiza reads
      final batch = FirebaseFirestore.instance.batch();


      final msgRef = _msgsRef.doc();


      batch.set(msgRef, {
        'text': text,
        'senderId': myUid,
        'createdAt': FieldValue.serverTimestamp(),
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
      });


      // ✅ patch completo do grupo (1 ÚNICO set merge) — NÃO usa update separado
      final Map<String, dynamic> patch = {
        'lastMessage': text,
        'lastSenderId': myUid,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'unread.$myUid': 0,
      };


      // incrementa unread pros outros membros
      for (final m in members) {
        if (m == myUid) continue;
        patch['unread.$m'] = FieldValue.increment(1);
      }


      batch.set(_groupRef, patch, SetOptions(merge: true));


      // mantém reads
      final readRef = _groupRef.collection('reads').doc(myUid);
      batch.set(readRef, {'lastReadAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));


      await batch.commit();
    } catch (e) {
      _toast('Erro ao enviar: $e');
    }
  }


  Future<void> _softDeleteMessage({
    required String messageId,
    required bool byAdmin,
  }) async {
    final myUid = uid;
    if (myUid == null) return;


    final label = byAdmin ? 'Mensagem apagada pelo admin' : 'Mensagem apagada';


    await _msgsRef.doc(messageId).set({
      'deleted': true,
      'deletedBy': myUid,
      'deletedText': label,
      'deletedAt': FieldValue.serverTimestamp(),
      'text': '',
    }, SetOptions(merge: true));
  }


  void _openInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInfoPage(groupId: widget.groupId),
      ),
    );
  }


  Future<void> _openActions({
    required String messageId,
    required bool isMyMessage,
  }) async {
    if (_loadingRole) return;
    final canDeleteForAll = _isAdmin;


    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            if (isMyMessage)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Apagar'),
                onTap: () async {
                  Navigator.pop(context);
                  await _softDeleteMessage(messageId: messageId, byAdmin: false);
                },
              ),
            if (canDeleteForAll)
              ListTile(
                leading: Icon(Icons.delete_forever_rounded, color: _remdyBlue),
                title: const Text('Apagar (admin)'),
                onTap: () async {
                  Navigator.pop(context);
                  await _softDeleteMessage(messageId: messageId, byAdmin: true);
                },
              ),
          ],
        ),
      ),
    );
  }


  Widget _groupAvatarFromData(Map<String, dynamic>? data) {
    final url = (data?['avatarUrl'] ?? '').toString().trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 34,
        height: 34,
        color: const Color(0xFFF1F5F9),
        child: url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.groups_rounded,
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
              )
            : const Icon(
                Icons.groups_rounded,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        scrolledUnderElevation: 0,
        elevation: 0,
        iconTheme: const IconThemeData(color: _muted),
        centerTitle: true,
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _groupRef.snapshots(),
          builder: (context, snap) {
            final gd = snap.data?.data();
            final name = (gd?['name'] ?? widget.groupName).toString().trim();


            return InkWell(
              onTap: _openInfo,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _groupAvatarFromData(gd),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        name.isEmpty ? widget.groupName : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _msgsRef.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Erro: ${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _muted),
                    ),
                  );
                }


                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Sem mensagens ainda.',
                      style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
                    ),
                  );
                }


                return ListView.builder(
                  controller: _scrollC,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final d = doc.data();


                    final senderId = (d['senderId'] ?? '').toString().trim();
                    final isMe = (uid != null && senderId == uid);


                    final deleted = (d['deleted'] == true);
                    final deletedText = (d['deletedText'] ?? '').toString().trim();


                    final text = deleted
                        ? (deletedText.isNotEmpty ? deletedText : 'Mensagem apagada pelo admin')
                        : (d['text'] ?? '').toString();


                    final bubbleWidget = _Bubble(
                      text: text,
                      isMe: isMe,
                      isDeleted: deleted,
                    );


                    final Widget bubble = senderId.isEmpty
                        ? bubbleWidget
                        : MessageRow(
                            senderUid: senderId,
                            isMe: isMe,
                            bubble: bubbleWidget,
                          );


                    return GestureDetector(
                      onLongPress: () async {
                        final canDelete = isMe || _isAdmin;
                        if (!canDelete) return;
                        await _openActions(messageId: doc.id, isMyMessage: isMe);
                      },
                      child: bubble,
                    );
                  },
                );
              },
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
  final bool isDeleted;


  const _Bubble({
    required this.text,
    required this.isMe,
    this.isDeleted = false,
  });


  static const Color _remdyBlue = Color(0xFF313A5F);


  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: isMe ? Colors.white : const Color(0xFF111827),
      fontWeight: FontWeight.w600,
      fontSize: isDeleted ? 12.5 : 14,
      fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
    );


    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? _remdyBlue : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMe ? _remdyBlue : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(text, style: style),
      ),
    );
  }
}


class MessageRow extends StatelessWidget {
  final String senderUid;
  final bool isMe;
  final Widget bubble;


  const MessageRow({
    required this.senderUid,
    required this.isMe,
    required this.bubble,
  });


  static const Color _muted = Color(0xFF6B7280);


  @override
  Widget build(BuildContext context) {
    final safeUid = senderUid.trim();
    if (safeUid.isEmpty) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      );
    }


    if (isMe) {
      return Align(
        alignment: Alignment.centerRight,
        child: bubble,
      );
    }


    final userRef = FirebaseFirestore.instance.collection('users').doc(safeUid);


    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userRef.snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data();
            final photoUrl = (data?['photoUrl'] ?? '').toString().trim();
            final avatarUrl = (data?['avatarUrl'] ?? '').toString().trim();
            final pic = photoUrl.isNotEmpty ? photoUrl : avatarUrl;


            return ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 22,
                height: 22,
                color: const Color(0xFFF1F5F9),
                child: pic.isNotEmpty
                    ? Image.network(pic, fit: BoxFit.cover)
                    : const Icon(Icons.person, size: 14, color: _muted),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: userRef.snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data();
              final name = (data?['name'] ?? 'Usuário').toString().trim();


              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      name.isEmpty ? 'Usuário' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Align(alignment: Alignment.centerLeft, child: bubble),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
