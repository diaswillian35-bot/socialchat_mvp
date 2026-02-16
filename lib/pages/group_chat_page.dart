import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ✅ AJUSTE o import conforme seu projeto
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
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  final _textC = TextEditingController();
  final _scrollC = ScrollController();

  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> get _groupRef =>
      FirebaseFirestore.instance.collection('groups').doc(widget.groupId);

  CollectionReference<Map<String, dynamic>> get _msgsRef =>
      _groupRef.collection('messages');

  bool _isAdmin = false; // ✅ cache local
  bool _loadingRole = true;

  @override
  void initState() {
    super.initState();
    _loadMyRole();
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
          ? adminsRaw
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList()
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

  Future<void> _send() async {
    final myUid = uid;
    if (myUid == null) return;

    final text = _textC.text.trim();
    if (text.isEmpty) return;

    _textC.clear();

    try {
      await _msgsRef.add({
        'text': text,
        'senderId': myUid, // ✅ mantém seu padrão
        'createdAt': FieldValue.serverTimestamp(),

        // ✅ suporte a soft-delete
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
      });

      // ✅ atualizar updatedAt do grupo (opcional mas bom)
      await _groupRef.set({
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
      'text': '', // ✅ apaga o texto original
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
    final myUid = uid;
    if (myUid == null) return;

    final canDeleteForAll = _isAdmin; // ✅ admin apaga de qualquer um

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
                  await _softDeleteMessage(
                    messageId: messageId,
                    byAdmin: false,
                  );
                },
              ),
            if (canDeleteForAll)
              ListTile(
                leading:
                    const Icon(Icons.delete_forever_rounded, color: Colors.red),
                title: const Text('Apagar (admin)'),
                onTap: () async {
                  Navigator.pop(context);
                  await _softDeleteMessage(
                    messageId: messageId,
                    byAdmin: true,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ✅ avatar do grupo (AppBar)
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

        // ✅ REMOVIDO O (i) — agora é SÓ título (clicável) + avatar do grupo
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _groupRef.snapshots(),
          builder: (context, snap) {
            final gd = snap.data?.data();
            final name = (gd?['name'] ?? widget.groupName).toString().trim();

            return InkWell(
              onTap: _openInfo,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
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
                    final doc = docs[i];
                    final d = doc.data();

                    final senderId = (d['senderId'] ?? '').toString();
                    final isMe = (uid != null && senderId == uid);

                    final deleted = (d['deleted'] == true);
                    final deletedText =
                        (d['deletedText'] ?? '').toString().trim();

                    final text = deleted
                        ? (deletedText.isNotEmpty
                            ? deletedText
                            : 'Mensagem apagada pelo admin')
                        : (d['text'] ?? '').toString();

                    final bubble = _MessageRow(
                      senderId: senderId,
                      isMe: isMe,
                      text: text,
                      isDeleted: deleted,
                    );

                    return GestureDetector(
                      onLongPress: () async {
                        if (_loadingRole) return;

                        final isMyMessage = isMe;
                        final canDelete = isMyMessage || _isAdmin;
                        if (!canDelete) return;

                        await _openActions(
                          messageId: doc.id,
                          isMyMessage: isMyMessage,
                        );
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

class _MessageRow extends StatelessWidget {
  final String senderId;
  final bool isMe;
  final String text;
  final bool isDeleted;

  const _MessageRow({
    required this.senderId,
    required this.isMe,
    required this.text,
    required this.isDeleted,
  });

  static const Color _textColor = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    // ✅ busca nome/foto do usuário (sem mudar o layout do bubble)
    final userRef = FirebaseFirestore.instance.collection('users').doc(senderId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        final ud = snap.data?.data();
        final name = (ud?['name'] ?? 'Usuário').toString().trim();

        final photoUrl = (ud?['photoUrl'] ?? '').toString().trim();
        final avatarUrl = (ud?['avatarUrl'] ?? '').toString().trim();
        final pic = photoUrl.isNotEmpty ? photoUrl : avatarUrl;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 28,
                    height: 28,
                    color: const Color(0xFFF1F5F9),
                    child: pic.isNotEmpty
                        ? Image.network(
                            pic,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.person,
                              size: 16,
                              color: Color(0xFF94A3B8),
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 16,
                            color: Color(0xFF94A3B8),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              Flexible(
                child: Column(
                  crossAxisAlignment:
                      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    // ✅ Nome do remetente (discreto)
                    if (!isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 2),
                        child: Text(
                          name.isEmpty ? 'Usuário' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),

                    _Bubble(
                      text: text,
                      isMe: isMe,
                      isDeleted: isDeleted,
                    ),
                  ],
                ),
              ),

              if (isMe) ...[
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 28,
                    height: 28,
                    color: const Color(0xFFF1F5F9),
                    child: const Icon(
                      Icons.person,
                      size: 16,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
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
