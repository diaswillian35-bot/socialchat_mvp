import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  // =========================
  // ✅ Remdy style
  // =========================
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);

  // =========================
  // ✅ Controllers
  // =========================
  final _nameC = TextEditingController();
  final _countryC = TextEditingController();
  final _bioC = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _nameC.dispose();
    _countryC.dispose();
    _bioC.dispose();
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

  // ✅ convite curto e estável
  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(rand.nextInt(chars.length))),
    );
  }

  Future<void> _create() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('Você precisa estar logado.');
      return;
    }

    final name = _nameC.text.trim();
    final country = _countryC.text.trim().toLowerCase(); // ✅ tudo minúsculo
    final bio = _bioC.text.trim();

    if (name.isEmpty) return _toast('Digite o nome do grupo.');
    if (country.isEmpty) return _toast('Digite o país (minúsculo).');

    if (_loading) return;
    setState(() => _loading = true);

    try {
      final inviteCode = _generateInviteCode();

      // ✅ cria documento
      await FirebaseFirestore.instance.collection('groups').add({
        'name': name,
        'country': country, // ✅ country (não countryCode)
        'bio': bio,
        'avatarUrl': '',
        'ownerId': user.uid,
        'admins': [user.uid],
        'members': [user.uid],

        // ✅ convite
        'inviteCode': inviteCode,
        'isPrivate': false,
        'joinPolicy': 'open', // open | approval | inviteOnly (depois)

        // ✅ timestamps
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context, true); // ✅ volta pra lista e atualiza
    } catch (e) {
      _toast('Erro ao criar grupo: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _logoBlue),
      ),
      labelStyle: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
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
        foregroundColor: _text,
        iconTheme: const IconThemeData(color: _muted),
        centerTitle: true,
        title: const Text(
          'Criar grupo',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_remdyBlue, _logoBlue]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              'Crie seu grupo (estilo WhatsApp)\nDepois a gente adiciona: foto, admins, link privado e aprovação.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _nameC,
            textInputAction: TextInputAction.next,
            decoration: _dec('Nome do grupo', hint: 'Ex: Brasileiros em Toronto'),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _countryC,
            textInputAction: TextInputAction.next,
            decoration: _dec('País (minúsculo)', hint: 'ex: canada, brasil, portugal'),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _bioC,
            maxLines: 4,
            decoration: _dec('Bio do grupo (opcional)', hint: 'Ex: encontros, futebol, amizade...'),
          ),

          const SizedBox(height: 18),

          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [_remdyBlue, _logoBlue]),
            ),
            child: ElevatedButton(
              onPressed: _loading ? null : _create,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Criar grupo',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
