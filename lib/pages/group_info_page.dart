import 'dart:io';


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_texts.dart';
import 'chat_page.dart';


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
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  String _buildInviteLink(String code) {
  return "https://remdy.app/g/$code";
}


  String _loadedLocaleCode = '';
  String _groupCode = '';


  final ImagePicker _picker = ImagePicker();


  bool _loading = true;
  bool _saving = false;


  Map<String, dynamic>? _groupData;
  List<Map<String, dynamic>> _membersData = [];


  String? get _uid => FirebaseAuth.instance.currentUser?.uid;


  DocumentReference<Map<String, dynamic>> get _groupRef =>
      FirebaseFirestore.instance.collection('groups').doc(widget.groupId);


  String _buildConversationId(String a, String b) {
    final ids = [a.trim(), b.trim()]..sort();
    return '${ids[0]}_${ids[1]}';
  }


  @override
  void initState() {
    super.initState();
    _loadAll();
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();


    final locale = Localizations.localeOf(context);
    final nextCode = '${locale.languageCode}_${locale.countryCode ?? ''}';


    if (_loadedLocaleCode == nextCode) return;
    _loadedLocaleCode = nextCode;


    AppTexts.load(locale).then((_) {
      if (mounted) setState(() {});
    });
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


  Future<void> _loadAll() async {
    final t = AppTexts.current;


    setState(() => _loading = true);


    try {
      final groupSnap = await _groupRef.get();
      final data = groupSnap.data() ?? {};
      _groupData = data;
      _groupCode = (data['inviteCode'] ?? '').toString().trim();


      final membersRaw = data['members'];
      final memberIds = (membersRaw is List)
          ? membersRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : <String>[];


      final loadedMembers = <Map<String, dynamic>>[];


      for (final uid in memberIds) {
        try {
          final userSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          final u = userSnap.data() ?? {};


          loadedMembers.add({
            'uid': uid,
            'name': (u['name'] ?? t.get('user')).toString(),
            'photoUrl': (u['photoUrl'] ?? '').toString(),
            'avatarUrl': (u['avatarUrl'] ?? '').toString(),
          });
        } catch (_) {
          loadedMembers.add({
            'uid': uid,
            'name': t.get('user'),
            'photoUrl': '',
            'avatarUrl': '',
          });
        }
      }


      if (!mounted) return;
      setState(() {
        _membersData = loadedMembers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('${t.get('errorLoadingGroup')}: $e');
    }
  }


  bool get _isAdmin {
    final myUid = _uid;
    if (myUid == null) return false;


    final adminsRaw = _groupData?['admins'];
    final admins = (adminsRaw is List)
        ? adminsRaw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];


    return admins.contains(myUid);
  }


  String _prettyCountry(String s) {
    final t = AppTexts.current;


    switch (s.trim().toLowerCase()) {
      case 'canada':
        return t.get('canada');
      case 'brasil':
      case 'brazil':
        return t.get('brazil');
      case 'portugal':
        return t.get('portugal');
      default:
        if (s.trim().isEmpty) return '--';
        return s.trim();
    }
  }


  String _joinPolicyLabel(String policy) {
    final t = AppTexts.current;


    switch (policy.trim().toLowerCase()) {
      case 'approval':
        return t.get('admin_approval');
      case 'inviteonly':
      case 'invite_only':
      case 'inviteonly ':
        return t.get('invite_only');
      default:
        return t.get('open_entry');
    }
  }


  String _joinPolicyValueFromLabel(String label) {
    final t = AppTexts.current;


    if (label == t.get('admin_approval')) {
      return 'approval';
    }
    if (label == t.get('invite_only')) {
      return 'inviteOnly';
    }
    return 'open';
  }


  Future<void> _savePatch(Map<String, dynamic> patch) async {
    final t = AppTexts.current;


    try {
      setState(() => _saving = true);
      await _groupRef.set(patch, SetOptions(merge: true));
      await _loadAll();
    } catch (e) {
      _toast('${t.get('errorSaving')}: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _editBio() async {
    final t = AppTexts.current;
    if (!_isAdmin) return;


    final controller = TextEditingController(
      text: (_groupData?['bio'] ?? '').toString(),
    );


    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.get('editBio')),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: t.get('typeGroupBio'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.get('save')),
          ),
        ],
      ),
    );


    if (ok != true) return;


    await _savePatch({
      'bio': controller.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }


  Future<void> _togglePrivate(bool value) async {
    if (!_isAdmin) return;


    await _savePatch({
      'isPrivate': value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }


  Future<void> _changeJoinPolicy(String? label) async {
    if (!_isAdmin || label == null) return;


    await _savePatch({
      'joinPolicy': _joinPolicyValueFromLabel(label),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

Future<void> _copyInviteCode() async {
  final t = AppTexts.current;


  final code = (_groupData?['inviteCode'] ?? '').toString().trim();
  if (code.isEmpty) {
    _toast(t.get('emptyInviteCode'));
    return;
  }


  final inviteLink = _groupCode.isEmpty ? '' : _buildInviteLink(_groupCode);


  await Clipboard.setData(ClipboardData(text: inviteLink));
  _toast(t.get('codeCopied'));
}



  Future<void> _pickGroupPhoto() async {
    final t = AppTexts.current;
    if (!_isAdmin) return;


    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );


      if (file == null) return;


      setState(() => _saving = true);


      final myUid = _uid ?? 'unknown';
      final ext = file.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';


      final ref = FirebaseStorage.instance
          .ref()
          .child('groups')
          .child(widget.groupId)
          .child('avatar')
          .child('group_avatar_$myUid.$ext');


      await ref.putFile(
        File(file.path),
        SettableMetadata(
          contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
        ),
      );


      final url = await ref.getDownloadURL();


      await _groupRef.set({
        'avatarUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));


      await _loadAll();
    } catch (e) {
      _toast('${t.get('errorUploadingGroupPhoto')}: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _approveJoinRequest(String requestUid) async {
    try {
      setState(() => _saving = true);


      final snap = await _groupRef.get();
      final data = snap.data() ?? {};


      final members = (data['members'] is List)
          ? List<String>.from(
              (data['members'] as List).map((e) => e.toString()),
            )
          : <String>[];


      final alreadyMember = members.contains(requestUid);


      await _groupRef.set({
        'members': FieldValue.arrayUnion([requestUid]),
        'membersCount': alreadyMember ? members.length : members.length + 1,
        'updatedAt': FieldValue.serverTimestamp(),
        'unread.$requestUid': 0,
      }, SetOptions(merge: true));


      await _groupRef.collection('joinRequests').doc(requestUid).set({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': _uid,
      }, SetOptions(merge: true));


      await _loadAll();


      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido aprovado ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao aprovar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _rejectJoinRequest(String requestUid) async {
    try {
      setState(() => _saving = true);


      await _groupRef.collection('joinRequests').doc(requestUid).set({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': _uid,
      }, SetOptions(merge: true));


      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido recusado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao recusar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _leaveGroup() async {
    final t = AppTexts.current;
    final myUid = _uid;
    if (myUid == null) return;


    final membersRaw = _groupData?['members'];
    final members = (membersRaw is List)
        ? membersRaw.map((e) => e.toString()).toList()
        : <String>[];


    if (!members.contains(myUid)) {
      _toast(t.get('youAreNoLongerInGroup'));
      return;
    }


    if (_isAdmin && members.length <= 1) {
      _toast(t.get('ownerCannotLeaveOnlyMember'));
      return;
    }


    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.get('leaveGroup')),
        content: Text(t.get('confirmLeaveGroup')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.get('leave')),
          ),
        ],
      ),
    );


    if (confirm != true) return;


    try {
      setState(() => _saving = true);


      final snap = await _groupRef.get();
      final data = snap.data() ?? {};
      final unreadMap = Map<String, dynamic>.from(data['unread'] ?? {});
      unreadMap.remove(myUid);


      final currentMembers = (data['members'] is List)
          ? List<String>.from(
              (data['members'] as List).map((e) => e.toString()),
            )
          : <String>[];


      final currentAdmins = (data['admins'] is List)
          ? List<String>.from(
              (data['admins'] as List).map((e) => e.toString()),
            )
          : <String>[];


      currentMembers.remove(myUid);
      currentAdmins.remove(myUid);


      if (currentAdmins.isEmpty && currentMembers.isNotEmpty) {
        currentAdmins.add(currentMembers.first);
      }


      await _groupRef.set({
        'members': currentMembers,
        'admins': currentAdmins,
        'membersCount': currentMembers.length,
        'updatedAt': FieldValue.serverTimestamp(),
        'unread': unreadMap,
      }, SetOptions(merge: true));


      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast('${t.get('errorLeavingGroup')}: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _deleteGroup() async {
    final t = AppTexts.current;
    if (!_isAdmin) return;


    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.get('deleteGroup')),
        content: Text(t.get('confirmDeleteGroup')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.get('delete')),
          ),
        ],
      ),
    );


    if (confirm != true) return;


    try {
      setState(() => _saving = true);


      await _groupRef.set({
        'deleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));


      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _toast('${t.get('errorDeletingGroup')}: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _openPrivateChatFromMember(Map<String, dynamic> m) async {
    final t = AppTexts.current;
    final myUid = _uid;
    if (myUid == null) return;


    final otherUid = (m['uid'] ?? '').toString().trim();
    final otherName = (m['name'] ?? t.get('user')).toString().trim();


    if (otherUid.isEmpty) {
      _toast(t.get('invalidUser'));
      return;
    }


    if (otherUid == myUid) {
      _toast(t.get('thisIsYourOwnProfile'));
      return;
    }


    try {
      final conversationId = _buildConversationId(myUid, otherUid);


      final convRef = FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId);


      final snap = await convRef.get();


      if (!snap.exists) {
        await convRef.set({
          'participants': [myUid, otherUid],
          'pairKey': conversationId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'lastMessageAt': null,
          'unread': {
            myUid: 0,
            otherUid: 0,
          },
        });
      }


      if (!mounted) return;


      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: conversationId,
            otherUid: otherUid,
            otherName: otherName.isEmpty ? t.get('user') : otherName,
          ),
        ),
      );
    } catch (e) {
      _toast('${t.get('errorOpeningConversation')}: $e');
    }
  }


  Widget _groupHeader() {
    final t = AppTexts.current;


    final name = (_groupData?['name'] ?? t.get('group')).toString().trim();
    final country = (_groupData?['country'] ?? '').toString().trim();
    final city = (_groupData?['city'] ?? '').toString().trim();
    final bio = (_groupData?['bio'] ?? '').toString().trim();
    final avatarUrl = (_groupData?['avatarUrl'] ?? '').toString().trim();
    final isPrivate = _groupData?['isPrivate'] == true;
    final joinPolicy = (_groupData?['joinPolicy'] ?? 'open').toString();
    final membersCount = _membersData.length;


    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_remdyBlue, Color(0xFF264E9A)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: avatarUrl.isNotEmpty
                      ? Image.network(
                          avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.groups_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        )
                      : const Icon(
                          Icons.groups_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
              ),
              if (_isAdmin)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: InkWell(
                    onTap: _saving ? null : _pickGroupPhoto,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white),
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        size: 16,
                        color: _remdyBlue,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? t.get('group') : name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${t.get('country_label')} ${_prettyCountry(country)} • ${t.get('city_label')} ${city.isEmpty ? "--" : city} • $membersCount ${membersCount == 1 ? t.get('member_singular') : t.get('member_plural')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    bio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(
                      icon: isPrivate ? Icons.lock : Icons.lock_open,
                      text: isPrivate ? t.get('private') : t.get('public'),
                    ),
                    _pill(
                      icon: Icons.how_to_reg_rounded,
                      text: _joinPolicyLabel(joinPolicy),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _pill({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }


  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }


  Widget _memberTile(Map<String, dynamic> m) {
    final t = AppTexts.current;


    final uid = (m['uid'] ?? '').toString();
    final name = (m['name'] ?? t.get('user')).toString();
    final photoUrl = (m['photoUrl'] ?? '').toString().trim();
    final avatarUrl = (m['avatarUrl'] ?? '').toString().trim();
    final pic = photoUrl.isNotEmpty ? photoUrl : avatarUrl;


    final adminsRaw = _groupData?['admins'];
    final admins = (adminsRaw is List)
        ? adminsRaw.map((e) => e.toString()).toList()
        : <String>[];


    final isAdmin = admins.contains(uid);
    final isMe = uid == _uid;


    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openPrivateChatFromMember(m),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 44,
                height: 44,
                color: const Color(0xFFF1F5F9),
                child: pic.isNotEmpty
                    ? Image.network(
                        pic,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.person),
                      )
                    : const Icon(Icons.person, color: _muted),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            if (isAdmin)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  t.get('admin'),
                  style: const TextStyle(
                    color: _remdyBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
            if (isMe)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  t.get('you'),
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }


  Widget _pendingRequestsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pedidos pendentes',
            style: TextStyle(
              color: _text,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _groupRef
                .collection('joinRequests')
                .where('status', isEqualTo: 'pending')
                .orderBy('createdAt', descending: false)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }


              final docs = snap.data?.docs ?? [];


              if (docs.isEmpty) {
                return const Text(
                  'Nenhum pedido pendente.',
                  style: TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }


              return Column(
                children: docs.map((reqDoc) {
                  final req = reqDoc.data();
                  final requestUid = (req['uid'] ?? '').toString().trim();


                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(requestUid)
                        .get(),
                    builder: (context, userSnap) {
                      final userData = userSnap.data?.data() ?? {};
                      final userName =
                          (userData['name'] ?? 'Usuário').toString().trim();
                      final photoUrl =
                          (userData['photoUrl'] ?? '').toString().trim();
                      final avatarUrl =
                          (userData['avatarUrl'] ?? '').toString().trim();
                      final pic = photoUrl.isNotEmpty ? photoUrl : avatarUrl;


                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _border),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 42,
                                height: 42,
                                color: const Color(0xFFF1F5F9),
                                child: pic.isNotEmpty
                                    ? Image.network(
                                        pic,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.person),
                                      )
                                    : const Icon(Icons.person, color: _muted),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                userName.isEmpty ? 'Usuário' : userName,
                                style: const TextStyle(
                                  color: _text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => _rejectJoinRequest(requestUid),
                              child: const Text('Recusar'),
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton(
                              onPressed: _saving
                                  ? null
                                  : () => _approveJoinRequest(requestUid),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _remdyBlue,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              child: const Text('Aprovar'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }


  Widget _settingsCard({
    required AppTexts t,
    required bool isPrivate,
    required String joinPolicy,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.get('settings'),
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.lock, color: _muted, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t.get('private_group'),
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Switch(
                value: isPrivate,
                activeColor: Colors.white,
                activeTrackColor: _remdyBlue,
                inactiveThumbColor: const Color(0xFF6B7280),
                inactiveTrackColor: const Color(0xFFE5E7EB),
                trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
                  (states) {
                    if (states.contains(WidgetState.selected)) {
                      return _remdyBlue;
                    }
                    return const Color(0xFFE5E7EB);
                  },
                ),
                onChanged: _isAdmin && !_saving ? _togglePrivate : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.how_to_reg_rounded,
                color: _muted,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                t.get('entry'),
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    canvasColor: Colors.white,
                    colorScheme: Theme.of(context).colorScheme.copyWith(
                          primary: _remdyBlue,
                        ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _joinPolicyLabel(joinPolicy),
                      isExpanded: true,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _muted,
                      ),
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: t.get('open_entry'),
                          child: Text(t.get('open_entry')),
                        ),
                        DropdownMenuItem(
                          value: t.get('admin_approval'),
                          child: Text(t.get('admin_approval')),
                        ),
                        DropdownMenuItem(
                          value: t.get('invite_only'),
                          child: Text(t.get('invite_only')),
                        ),
                      ],
                      onChanged:
                          _isAdmin && !_saving ? _changeJoinPolicy : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


@override
Widget build(BuildContext context) {
  final t = AppTexts.current;
  final inviteLink = _groupCode.isEmpty ? '' : _buildInviteLink(_groupCode);


  final bio = (_groupData?['bio'] ?? '').toString().trim();
  final isPrivate = _groupData?['isPrivate'] == true;
  final joinPolicy = (_groupData?['joinPolicy'] ?? 'open').toString();


    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          t.get('group_info'),
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: _text),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _groupHeader(),
                    const SizedBox(height: 14),


                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.get('bio'),
                                  style: const TextStyle(
                                    color: _text,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              if (_isAdmin)
                                InkWell(
                                  onTap: _saving ? null : _editBio,
                                  child: Text(
                                    t.get('edit'),
                                    style: const TextStyle(
                                      color: _remdyBlue,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            bio.isEmpty ? '-' : bio,
                            style: const TextStyle(
                              color: _muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),


                    if (_isAdmin && joinPolicy == 'approval') ...[
                      _pendingRequestsCard(),
                      const SizedBox(height: 14),
                    ],


                  if (_isAdmin) ...[
  _settingsCard(
    t: t,
    isPrivate: isPrivate,
    joinPolicy: joinPolicy,
  ),
  const SizedBox(height: 14),
],



                    _card(
  child: Row(
    children: [
      const Icon(Icons.link_rounded, color: _muted, size: 18),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          inviteLink.isEmpty ? '--' : inviteLink,
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      InkWell(
        onTap: inviteLink.isEmpty
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: inviteLink));
                _toast(t.get('group_code_copied'));
              },
        child: Text(
          t.get('copy'),
          style: const TextStyle(
            color: _remdyBlue,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
      const SizedBox(width: 12),
      InkWell(
        onTap: inviteLink.isEmpty
            ? null
            : () async {
                await Share.share(inviteLink);
              },
        child: Text(
          t.get('share'),
          style: const TextStyle(
            color: _remdyBlue,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    ],
  ),
),

const SizedBox(height: 14),



                    Text(
                      '${t.get('members')} ${_membersData.length}',
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._membersData.map(_memberTile),
                    const SizedBox(height: 16),


                    _card(
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : _leaveGroup,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _remdyBlue,
                                side: const BorderSide(color: _border),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              icon: const Icon(Icons.logout_rounded),
                              label: Text(
                                t.get('leave_group'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          if (_isAdmin) ...[
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: _saving ? null : _deleteGroup,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.delete_outline_rounded,
                                      color: _muted,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      t.get('delete_group'),
                                      style: const TextStyle(
                                        color: _muted,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (_saving)
                  Container(
                    color: Colors.black.withOpacity(0.05),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
              ],
            ),
    );
  }
}
