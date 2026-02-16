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

  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);

  final _nameC = TextEditingController();
  final _countryC = TextEditingController();
  final _cityC = TextEditingController(); // NOVO
  final _bioC = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _nameC.dispose();
    _countryC.dispose();
    _cityC.dispose();
    _bioC.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(rand.nextInt(chars.length))),
    );
  }

  Future<void> _create() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _toast('Você precisa estar logado.');

    final name = _nameC.text.trim();
    final country = _countryC.text.trim().toLowerCase();
    final city = _cityC.text.trim(); // NOVO
    final bio = _bioC.text.trim();

    if (name.isEmpty) return _toast('Digite o nome do grupo.');
    if (country.isEmpty) return _toast('Digite o país.');
    if (city.isEmpty) return _toast('Digite a cidade.');

    setState(() => _loading = true);

    try {
      final inviteCode = _generateInviteCode();

      await FirebaseFirestore.instance.collection('groups').add({
        'name': name,
        'country': country,
        'city': city, // NOVO
        'bio': bio,
        'avatarUrl': '',
        'ownerId': user.uid,
        'admins': [user.uid],
        'members': [user.uid],
        'inviteCode': inviteCode,
        'isPrivate': false,
        'joinPolicy': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context, true);
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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text('Criar grupo', style: TextStyle(color: _text)),
        iconTheme: const IconThemeData(color: _muted),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameC,
            decoration: _dec('Nome do grupo'),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _countryC,
            decoration: _dec('País'),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _cityC,
            decoration: _dec('Cidade'), // NOVO
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _bioC,
            maxLines: 3,
            decoration: _dec('Bio'),
          ),

          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: _loading ? null : _create,
            style: ElevatedButton.styleFrom(
              backgroundColor: _remdyBlue,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Criar grupo'),
          ),
        ],
      ),
    );
  }
}
