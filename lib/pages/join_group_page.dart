import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widget/remdy_app.dart';

// ✅ Ajuste se você quiser abrir o chat direto após entrar:
// import 'group_chat_page.dart';

// ✅ Se você já tem PremiumPage, ajuste o import:
// import 'premium_page.dart';

class JoinGroupPage extends StatefulWidget {
  final String inviteCode; // vem do link ?code=XXXXXX

  const JoinGroupPage({
    super.key,
    required this.inviteCode,
  });

  @override
  State<JoinGroupPage> createState() => _JoinGroupPageState();
}

class _JoinGroupPageState extends State<JoinGroupPage> {
  // ✅ Remdy style
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
        setState(() {
          _error = 'Convite inválido ou expirado.';
          _loading = false;
        });
        return;
      }

      setState(() {
        _groupDoc = q.docs.first;
        _loading = false;
      });
    } catch (e) {
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
      final data = snap.data();
      final v = data?['isPremium'];
      return v == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _join() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('Faça login primeiro para entrar no grupo.');
      return;
    }
    if (_groupDoc == null) return;

    if (_joining) return;
    setState(() => _joining = true);

    try {
      final doc = _groupDoc!;
      final groupId = doc.id;
      final data = doc.data() ?? {};

      final String name = (data['name'] ?? 'Grupo').toString().trim();
      final bool isPremiumGroup = (data['isPremiumGroup'] == true);
      final String joinPolicy = (data['joinPolicy'] ?? 'open').toString().trim();
      // joinPolicy: open | approval | inviteOnly

      // ✅ grupo premium -> exige premium
      if (isPremiumGroup) {
        final premium = await _isUserPremium(user.uid);
        if (!premium) {
          _toast('Esse grupo é Premium. Faça upgrade para entrar.');
          // Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumPage()));
          setState(() => _joining = false);
          return;
        }
      }

      final groupRef =
          FirebaseFirestore.instance.collection('groups').doc(groupId);

      // ✅ approval: cria solicitação (não entra direto)
      if (joinPolicy == 'approval') {
        final reqRef = groupRef.collection('joinRequests').doc(user.uid);

        await reqRef.set({
          'uid': user.uid,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        _toast('Pedido enviado ✅ Aguardando aprovação do admin.');
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }

      // ✅ open OU inviteOnly (aqui o convite é válido, então pode entrar direto)
      // 🔒 não duplica: arrayUnion já protege
      await groupRef.set({
        'members': FieldValue.arrayUnion([user.uid]),
        'updatedAt': FieldValue.serverTimestamp(),
        // ✅ PATCH: mantém contador coerente
        'membersCount': FieldValue.increment(1),
      }, SetOptions(merge: true));

      // ✅ opcional: salva “último join” no user
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'lastJoinedGroupId': groupId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _toast('Entrou no grupo ✅');

      if (!mounted) return;

      // ✅ Melhor UX: abre chat direto (descomente quando tiver o import certo)
      // Navigator.pushReplacement(
      //   context,
      //   MaterialPageRoute(
      //     builder: (_) => GroupChatPage(groupId: groupId, groupName: name),
      //   ),
      // );

      // ✅ Alternativa: só voltar pra tela anterior
      Navigator.pop(context, true);
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
    final bio = (group['bio'] ?? '').toString().trim();

    final isPremiumGroup = (group['isPremiumGroup'] == true);
    final joinPolicy = (group['joinPolicy'] ?? 'open').toString().trim();

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
                            'País: ${country.isEmpty ? '--' : country}',
                            style: const TextStyle(
                              color: _muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (bio.isNotEmpty)
                            Text(
                              bio,
                              style: const TextStyle(
                                color: _muted,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
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
                                text: joinPolicy == 'approval'
                                    ? 'Aprovação'
                                    : (joinPolicy == 'inviteOnly'
                                        ? 'Somente convite'
                                        : 'Entrada livre'),
                                filled: false,
                              ),
                              _Tag(text: 'Code: $_code', filled: false),
                            ],
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
                                joinPolicy == 'approval'
                                    ? 'Pedir para entrar'
                                    : 'Entrar no grupo',
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

  const _Tag({required this.text, required this.filled});

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
