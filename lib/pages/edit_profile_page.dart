import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'splash_page.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final _nameC = TextEditingController();
  final _ageC = TextEditingController();
  final _nativeC = TextEditingController();
  final _aboutC = TextEditingController();

  String _studyingCode = 'en';
  bool _loading = true;
  bool _saving = false;
  String? _err;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  static const _langs = [
    _LangItem(code: 'en', name: 'Inglês'),
    _LangItem(code: 'fr', name: 'Francês'),
    _LangItem(code: 'es', name: 'Espanhol'),
    _LangItem(code: 'pt', name: 'Português'),
    _LangItem(code: 'it', name: 'Italiano'),
    _LangItem(code: 'de', name: 'Alemão'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _publicDoc(String uid) =>
      FirebaseFirestore.instance.collection('publicUsers').doc(uid);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final uid = _myUid;
      if (uid == null) {
        _err = 'Você precisa estar logado para editar o perfil.';
        return;
      }

      final snap = await _userDoc(uid).get();
      final data = snap.data() ?? {};

      _nameC.text = (data['name'] ?? '').toString();
      _ageC.text = (data['age'] ?? '').toString();
      _nativeC.text = (data['nativeLanguage'] ?? '').toString();
      _aboutC.text = (data['about'] ?? '').toString();

      final raw = (data['studyingLanguageCode'] ?? 'en').toString().trim();
      final validCodes = _langs.map((l) => l.code).toSet();
      _studyingCode = validCodes.contains(raw) ? raw : 'en';
    } catch (e) {
      _err = 'Erro ao carregar perfil: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _err = null;
    });

    try {
      final uid = _myUid;
      if (uid == null) {
        setState(() => _err = 'Você precisa estar logado para salvar o perfil.');
        return;
      }

      final name = _nameC.text.trim();
      final nativeLanguage = _nativeC.text.trim();
      final about = _aboutC.text.trim();

      final ageText = _ageC.text.trim();
      int? age;
      if (ageText.isNotEmpty) {
        age = int.tryParse(ageText);
      }

      final authUser = FirebaseAuth.instance.currentUser;
      final email = authUser?.email ?? '';
      final photoUrl = authUser?.photoURL ?? '';

      final now = FieldValue.serverTimestamp();

      // ✅ Só define createdAt se ainda não existir (senão você perde o "criado em")
      final userSnap = await _userDoc(uid).get();
      final userData = userSnap.data() ?? {};
      final hasUserCreatedAt = userData.containsKey('createdAt') && userData['createdAt'] != null;

      final pubSnap = await _publicDoc(uid).get();
      final pubData = pubSnap.data() ?? {};
      final hasPubCreatedAt = pubData.containsKey('createdAt') && pubData['createdAt'] != null;

      // 1) SALVA PERFIL PRIVADO (users)
      final userPayload = <String, dynamic>{
        'uid': uid,
        'name': name,
        'age': age,
        'nativeLanguage': nativeLanguage,
        'about': about,
        'studyingLanguageCode': _studyingCode,

        // ✅ ESSENCIAL: Splash libera a Home quando isso for true
        'profileComplete': true,

        'updatedAt': now,
      };

      if (!hasUserCreatedAt) {
        userPayload['createdAt'] = now;
      }

      await _userDoc(uid).set(userPayload, SetOptions(merge: true));

      // 2) PERFIL PÚBLICO (publicUsers)
      final publicPayload = <String, dynamic>{
        'uid': uid,
        'name': name,
        'country': '', // se você preencher em outra tela depois, ok
        'about': about,
        'nativeLanguage': nativeLanguage,
        'studyingLanguageCode': _studyingCode,

        'isOnline': true,
        'lastSeenAt': now,

        'email': email,
        'photoUrl': photoUrl,

        'updatedAt': now,
      };

      if (!hasPubCreatedAt) {
        publicPayload['createdAt'] = now;
      }

      await _publicDoc(uid).set(publicPayload, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil salvo ✅')),
      );

      // ✅ Depois de salvar: volta pro Splash e limpa a pilha
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SplashPage()),
        (_) => false,
      );
    } catch (e) {
      setState(() => _err = 'Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameC.dispose();
    _ageC.dispose();
    _nativeC.dispose();
    _aboutC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_myUid == null) {
      return const Scaffold(
        body: Center(child: Text('Você precisa estar logado para editar o perfil.')),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Editar perfil')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // ✅ proteção extra p/ dropdown
    final uniqueLangs = <String, _LangItem>{};
    for (final l in _langs) {
      uniqueLangs[l.code] = l;
    }
    final langsList = uniqueLangs.values.toList();
    final validCodes = langsList.map((e) => e.code).toSet();
    final dropdownValue = validCodes.contains(_studyingCode) ? _studyingCode : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar perfil'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_err != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _err!,
                style: TextStyle(
                  color: Colors.red.shade900,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameC,
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Digite seu nome';
                    if (v.trim().length < 2) return 'Nome muito curto';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ageC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Idade',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    final n = int.tryParse(t);
                    if (n == null) return 'Digite um número';
                    if (n < 13) return 'Idade mínima: 13';
                    if (n > 99) return 'Idade inválida';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nativeC,
                  decoration: const InputDecoration(
                    labelText: 'Língua nativa',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: dropdownValue,
                  items: langsList
                      .map((l) => DropdownMenuItem(
                            value: l.code,
                            child: Text(l.name),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _studyingCode = v);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Estudando',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _aboutC,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Sobre você',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Salvando...' : 'Salvar'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LangItem {
  final String code;
  final String name;
  const _LangItem({required this.code, required this.name});
}
