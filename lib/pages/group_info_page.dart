 import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'private_chat_page.dart';

class GroupInfoPage extends StatefulWidget {
  final String groupId;

  const GroupInfoPage({
    super.key,
    required this.groupId,
  });

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  // ✅ Remdy style
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);

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

  String _prettyCountry(String raw) {
    final c = raw.trim();
    if (c.isEmpty) return '--';
    return c.length <= 3 ? c.toUpperCase() : c;
  }

  int _membersCountFromData(Map<String, dynamic> data, List<String> members) {
    if (members.isNotEmpty) return members.length;
    final mc = data['membersCount'];
    if (mc is int) return mc;
    return 0;
  }

  List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  Future<void> _copyInvite(String inviteCode) async {
    try {
      await Clipboard.setData(ClipboardData(text: inviteCode));
      _toast('Código copiado: $inviteCode');
    } catch (_) {
      _toast('Não consegui copiar. Código: $inviteCode');
    }
  }

  Future<void> _editBio(DocumentReference<Map<String, dynamic>> groupRef, String currentBio) async {
    final c = TextEditingController(text: currentBio);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar Bio'),
        content: TextField(
          controller: c,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Escreva a bio do grupo...',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );

    if (ok != true) return;

    await groupRef.set({
      'bio': c.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _toast('Bio atualizada ✅');
  }

  @override
  Widget build(BuildContext context) {
    final groupRef = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);

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
          'Info do grupo',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: groupRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}'));
          }

          final data = snap.data?.data();
          if (data == null) {
            return const Center(child: Text('Grupo não encontrado.'));
          }

          final myUid = FirebaseAuth.instance.currentUser?.uid;

          final name = (data['name'] ?? 'Grupo').toString().trim();
          final bio = (data['bio'] ?? '').toString().trim();

          final countryRaw = (data['country'] ?? '').toString().trim();
          final country = _prettyCountry(countryRaw);

          final cityRaw = (data['city'] ?? '').toString().trim();
          final city = cityRaw.isEmpty ? '--' : cityRaw;

          final avatarUrl = (data['avatarUrl'] ?? '').toString().trim();
          final ownerId = (data['ownerId'] ?? '').toString().trim();

          final admins = _asStringList(data['admins']);
          final members = _asStringList(data['members']);
          final membersCount = _membersCountFromData(data, members);

          final inviteCode = (data['inviteCode'] ?? '').toString().trim();
          final isPrivate = (data['isPrivate'] == true);
          final joinPolicy = (data['joinPolicy'] ?? 'open').toString().trim(); // open | approval | inviteOnly

          String joinPolicyLabel(String jp) {
            if (jp == 'approval') return 'Aprovação do admin';
            if (jp == 'inviteOnly') return 'Somente por convite';
            return 'Entrada livre';
          }

          final canEdit = (myUid != null && ((myUid == ownerId) || admins.contains(myUid)));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              // ✅ Header (mantém seu layout)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_remdyBlue, _logoBlue]),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 64,
                        height: 64,
                        color: Colors.white.withOpacity(0.18),
                        child: avatarUrl.isNotEmpty
                            ? Image.network(avatarUrl, fit: BoxFit.cover)
                            : const Icon(Icons.groups_rounded, color: Colors.white, size: 30),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? 'Grupo' : name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'País: $country • Cidade: $city • $membersCount membros',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _ChipWhite(
                                icon: Icons.lock_rounded,
                                label: isPrivate ? 'Privado' : 'Público',
                              ),
                              _ChipWhite(
                                icon: Icons.how_to_reg_rounded,
                                label: joinPolicyLabel(joinPolicy),
                              ),
                              if (canEdit)
                                const _ChipWhite(
                                  icon: Icons.shield_rounded,
                                  label: 'Você é admin',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ✅ Bio (mesmo layout + botão editar para admin)
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Bio',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _text,
                            fontSize: 14,
                          ),
                        ),
                        if (canEdit)
                          TextButton(
                            onPressed: () => _editBio(groupRef, bio),
                            child: const Text(
                              'Editar',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bio.isEmpty ? 'Sem bio ainda.' : bio,
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ✅ Configurações (apenas admin) - card igual ao resto
              if (canEdit) ...[
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
                      const Text(
                        'Configurações',
                        style: TextStyle(fontWeight: FontWeight.w900, color: _text, fontSize: 14),
                      ),
                      const SizedBox(height: 10),

                      // Privado/Público
                      Row(
                        children: [
                          const Icon(Icons.lock_rounded, color: _muted, size: 18),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Grupo privado',
                              style: TextStyle(fontWeight: FontWeight.w700, color: _text),
                            ),
                          ),
                          Switch(
                            value: isPrivate,
                            onChanged: (v) async {
                              await groupRef.set({
                                'isPrivate': v,
                                'updatedAt': FieldValue.serverTimestamp(),
                              }, SetOptions(merge: true));
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // joinPolicy
                      Row(
                        children: [
                          const Icon(Icons.how_to_reg_rounded, color: _muted, size: 18),
                          const SizedBox(width: 10),
                          const Text(
                            'Entrada:',
                            style: TextStyle(fontWeight: FontWeight.w800, color: _text),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: joinPolicy,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(value: 'open', child: Text('Entrada livre')),
                                  DropdownMenuItem(value: 'approval', child: Text('Aprovação do admin')),
                                  DropdownMenuItem(value: 'inviteOnly', child: Text('Somente por convite')),
                                ],
                                onChanged: (v) async {
                                  if (v == null) return;
                                  await groupRef.set({
                                    'joinPolicy': v,
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  }, SetOptions(merge: true));
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ✅ Código convite (igual)
              if (inviteCode.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link_rounded, color: _muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Código convite: $inviteCode',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => _copyInvite(inviteCode),
                        child: const Text(
                          'Copiar',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ✅ Membros (igual)
              Row(
                children: [
                  const Text(
                    'Membros',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: _text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$membersCount',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (members.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      'Sem membros.',
                      style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
                    ),
                  ),
                )
              else
                ...members.map(
                  (muid) => _MemberTile(
                    uid: muid,
                    ownerId: ownerId,
                    admins: admins,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ChipWhite extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ChipWhite({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final String uid;
  final String ownerId;
  final List<String> admins;

  const _MemberTile({
    required this.uid,
    required this.ownerId,
    required this.admins,
  });

  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  void _openPrivateChat(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    if (myUid == uid) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PrivateChatPage(otherUid: uid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);

    // ✅ dono vira admin também (como você pediu)
    final isOwner = uid == ownerId;
    final isAdmin = isOwner || admins.contains(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();

        final name = (data?['name'] ?? 'Usuário').toString().trim();

        final photoUrl = (data?['photoUrl'] ?? '').toString().trim();
        final avatarUrl = (data?['avatarUrl'] ?? '').toString().trim();
        final pic = photoUrl.isNotEmpty ? photoUrl : avatarUrl;

        return InkWell(
          onTap: () => _openPrivateChat(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 46,
                    height: 46,
                    color: Colors.grey.shade200,
                    child: pic.isNotEmpty
                        ? Image.network(pic, fit: BoxFit.cover)
                        : const Icon(Icons.person, size: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Usuário' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (isAdmin) _miniTag('Admin', Icons.shield_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.chevron_right_rounded, color: _muted),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _miniTag(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _remdyBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _remdyBlue.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _remdyBlue),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: _remdyBlue,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
