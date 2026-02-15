import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'private_chat_page.dart';

class GroupInfoPage extends StatelessWidget {
  final String groupId;

  const GroupInfoPage({
    super.key,
    required this.groupId,
  });

  // ✅ Remdy style
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);

  void _toast(BuildContext context, String msg) {
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
    // mostra bonito sem mudar o banco
    return c.length <= 3 ? c.toUpperCase() : c;
  }

  int _membersCountFromData(Map<String, dynamic> data, List<String> members) {
    if (members.isNotEmpty) return members.length;
    final mc = data['membersCount'];
    if (mc is int) return mc;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final groupRef = FirebaseFirestore.instance.collection('groups').doc(groupId);

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

          final avatarUrl = (data['avatarUrl'] ?? '').toString().trim();

          final ownerId = (data['ownerId'] ?? '').toString().trim();

          final adminsRaw = data['admins'];
          final admins = (adminsRaw is List)
              ? adminsRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
              : <String>[];

          final membersRaw = data['members'];
          final members = (membersRaw is List)
              ? membersRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
              : <String>[];

          final membersCount = _membersCountFromData(data, members);

          final inviteCode = (data['inviteCode'] ?? '').toString().trim();
          final isPrivate = (data['isPrivate'] == true);
          final joinPolicy = (data['joinPolicy'] ?? 'open').toString().trim(); // open | approval | inviteOnly

          String joinPolicyLabel() {
            if (joinPolicy == 'approval') return 'Aprovação do admin';
            if (joinPolicy == 'inviteOnly') return 'Somente por convite';
            return 'Entrada livre';
          }

          final isMeOwner = (myUid != null && myUid == ownerId);
          final isMeAdmin = (myUid != null && admins.contains(myUid));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              // ✅ Header estilo WhatsApp
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
                            'País: $country • $membersCount membros',
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
                                label: joinPolicyLabel(),
                              ),
                              if (isMeOwner)
                                const _ChipWhite(icon: Icons.verified_rounded, label: 'Você é dono'),
                              if (!isMeOwner && isMeAdmin)
                                const _ChipWhite(icon: Icons.shield_rounded, label: 'Você é admin'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ✅ Bio
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
                      'Bio',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _text,
                        fontSize: 14,
                      ),
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

              // ✅ Link de convite (somente mostra se existir)
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
                        onPressed: () {
                          // Sem Clipboard aqui pra não quebrar import; se quiser, eu coloco depois.
                          _toast(context, 'Copie o código: $inviteCode');
                        },
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

              // ✅ Membros
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
                  (uid) => _MemberTile(
                    uid: uid,
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
    final isOwner = uid == ownerId;
    final isAdmin = admins.contains(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();

        final name = (data?['name'] ?? 'Usuário').toString().trim();

        // aceita photoUrl OU avatarUrl (pra não quebrar)
        final photoUrl = ((data?['photoUrl'] ?? '') as dynamic).toString().trim();
        final avatarUrl = ((data?['avatarUrl'] ?? '') as dynamic).toString().trim();
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
                          if (isOwner)
                            _miniTag('Dono', Icons.star_rounded),
                          if (!isOwner && isAdmin)
                            _miniTag('Admin', Icons.shield_rounded),
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
