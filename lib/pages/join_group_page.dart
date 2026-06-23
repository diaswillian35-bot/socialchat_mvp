import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


import '../widget/remdy_app.dart';
import 'group_chat_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter/services.dart';

class JoinGroupPage extends StatefulWidget {
  final String inviteCode;


  const JoinGroupPage({
    super.key,
    required this.inviteCode,
  });


  @override
  State<JoinGroupPage> createState() => _JoinGroupPageState();
}


class _JoinGroupPageState extends State<JoinGroupPage> {
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);


  bool _loading = true;
  bool _joining = false;


  DocumentSnapshot<Map<String, dynamic>>? _groupDoc;
  String? _error;


  String get _code => widget.inviteCode.trim().toUpperCase();


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


  @override
  void initState() {
    super.initState();
    _loadGroupByCode();
  }


  Future<void> _loadGroupByCode() async {
    if (!mounted) return;


    setState(() {
      _loading = true;
      _error = null;
      _groupDoc = null;
    });


    try {
      final q = await FirebaseFirestore.instance
          .collection('groups')
          .where('inviteCode', isEqualTo: _code)
          .limit(1)
          .get();


      if (q.docs.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'Convite inválido ou expirado.';
          _loading = false;
        });
        return;
      }


      final doc = q.docs.first;
      final data = doc.data();
      final deleted = data['deleted'] == true;


      if (deleted) {
        if (!mounted) return;
        setState(() {
          _error = 'Convite inválido ou expirado.';
          _loading = false;
        });
        return;
      }


      if (!mounted) return;
      setState(() {
        _groupDoc = doc;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar convite: $e';
        _loading = false;
      });
    }
  }


  Future<bool> _isUserPremium(String uid) async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data() ?? {};
      return data['isPremium'] == true;
    } catch (_) {
      return false;
    }
  }


  Future<void> _openGroupChat({
    required String groupId,
    required String groupName,
  }) async {
    if (!mounted) return;


    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          groupId: groupId,
          groupName: groupName,
        ),
      ),
    );
  }


  Future<void> _join() async {
    final user = FirebaseAuth.instance.currentUser;


    if (user == null) {
      _toast('Faça login primeiro para entrar no grupo.');
      return;
    }


    if (_groupDoc == null || _joining) return;


    setState(() => _joining = true);


    try {
      final doc = _groupDoc!;
      final groupId = doc.id;
      final data = doc.data() ?? {};


      final String name = (data['name'] ?? 'Grupo').toString().trim();
      final bool isPremiumGroup = data['isPremiumGroup'] == true;
      final String joinPolicy =
          (data['joinPolicy'] ?? 'open').toString().trim();


      final membersRaw = data['members'];
      final members = (membersRaw is List)
          ? membersRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : <String>[];


      final alreadyMember = members.contains(user.uid);


      if (isPremiumGroup) {
        final premium = await _isUserPremium(user.uid);
        if (!premium) {
          _toast('Esse grupo é Premium. Faça upgrade para entrar.');
          if (mounted) setState(() => _joining = false);
          return;
        }
      }


      final groupRef =
          FirebaseFirestore.instance.collection('groups').doc(groupId);


      if (joinPolicy == 'approval' && !alreadyMember) {
       final reqRef = groupRef.collection('pendingRequests').doc(user.uid);
        final reqSnap = await reqRef.get();
        final reqData = reqSnap.data();
        final currentStatus = (reqData?['status'] ?? '').toString().trim();


      if (currentStatus == 'pending') {
  _toast('Seu pedido já está pendente de aprovação.');

  await Future.delayed(const Duration(milliseconds: 700));

  if (!mounted) return;

  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  } else {
    SystemNavigator.pop();
  }

  return;
}



      await reqRef.set({
  'uid': user.uid,
  'status': 'pending',
  'createdAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));

if (!mounted) return;

ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(
    content: Text('Pedido enviado ✅ Aguardando aprovação do admin.'),
  ),
);

await Future.delayed(const Duration(milliseconds: 700));

if (!mounted) return;

if (Navigator.of(context).canPop()) {
  Navigator.of(context).pop();
} else {
  SystemNavigator.pop();
}

return;



      }


      if (!alreadyMember) {
        await groupRef.set({
          'members': FieldValue.arrayUnion([user.uid]),
          'updatedAt': FieldValue.serverTimestamp(),
          'membersCount': FieldValue.increment(1),
          'unread.${user.uid}': 0,
        }, SetOptions(merge: true));
      } else {
        await groupRef.set({
          'updatedAt': FieldValue.serverTimestamp(),
          'unread.${user.uid}': 0,
        }, SetOptions(merge: true));
      }


      await groupRef.collection('reads').doc(user.uid).set({
        'lastReadAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));


      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'lastJoinedGroupId': groupId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));


      if (!alreadyMember) {
        _toast('Entrou no grupo ✅');
      } else {
        _toast('Você já faz parte deste grupo ✅');
      }


      await _openGroupChat(
        groupId: groupId,
        groupName: name.isEmpty ? 'Grupo' : name,
      );
    } catch (e) {
      _toast('Erro ao entrar: $e');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final group = _groupDoc?.data() ?? {};


    final name = (group['name'] ?? 'Grupo').toString().trim();
    final country = (group['country'] ?? '').toString().trim();
    final city = (group['city'] ?? '').toString().trim();
    final bio = (group['bio'] ?? '').toString().trim();
    final avatarUrl = (group['avatarUrl'] ?? '').toString().trim();


    final isPremiumGroup = group['isPremiumGroup'] == true;
    final joinPolicy = (group['joinPolicy'] ?? 'open').toString().trim();


    final joinButtonText = joinPolicy == 'approval'
        ? 'Pedir para entrar'
        : 'Entrar no grupo';


    final joinPolicyLabel = joinPolicy == 'approval'
        ? 'Aprovação'
        : (joinPolicy == 'inviteOnly' ? 'Somente convite' : 'Entrada livre');


    return Scaffold(
      backgroundColor: _bg,
      appBar: const RemdyAppBar(title: 'Entrar no grupo'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _border),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: avatarUrl.isNotEmpty
                                  ? Image.network(
                                      avatarUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.groups_rounded),
                                    )
                                  : const Icon(
                                      Icons.groups_rounded,
                                      color: _remdyBlue,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? 'Grupo' : name,
                                  style: const TextStyle(
                                    color: _text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'País: ${country.isEmpty ? '--' : country} • Cidade: ${city.isEmpty ? '--' : city}',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (bio.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    bio,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _Tag(
                                      text: isPremiumGroup ? 'Premium' : 'Free',
                                      filled: isPremiumGroup,
                                    ),
                                    _Tag(
                                      text: joinPolicyLabel,
                                      filled: false,
                                    ),
                                    _Tag(
                                      text: 'Code: $_code',
                                      filled: false,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: _remdyBlue,
                      ),
                      child: ElevatedButton(
                        onPressed: _joining ? null : _join,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _joining
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                joinButtonText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Obs: se você não estiver logado, faça login primeiro.',
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
    );
  }
}


class _Tag extends StatelessWidget {
  final String text;
  final bool filled;


  const _Tag({
    required this.text,
    required this.filled,
  });


  static const Color _remdyBlue = Color(0xFF313A5F);


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? _remdyBlue : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: filled ? _remdyBlue : const Color(0xFFE5E7EB),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: filled ? Colors.white : const Color(0xFF111827),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
