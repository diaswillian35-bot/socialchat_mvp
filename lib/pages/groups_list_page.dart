import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';


import 'create_group_page.dart';
import 'group_chat_page.dart';
import '../l10n/app_texts.dart';


class GroupsListPage extends StatefulWidget {
  const GroupsListPage({super.key});


  @override
  State<GroupsListPage> createState() => _GroupsListPageState();
}


class _GroupsListPageState extends State<GroupsListPage> {
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);


  String _selectedCountry = 'all';
  final TextEditingController _searchC = TextEditingController();
  bool _showBanner = true;
  String _myCity = '';
String _myCountryCode = '';
String _myCountryName = '';
bool _isPremium = false;


  String _loadedLocaleCode = '';


  List<Map<String, String>> get _countries => [
        {'code': 'all', 'name': AppTexts.current.get('all')},
        {'code': 'brasil', 'name': AppTexts.current.get('country_brazil')},
        {'code': 'canada', 'name': AppTexts.current.get('country_canada')},
        {'code': 'portugal', 'name': AppTexts.current.get('country_portugal')},
      ];


  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

Future<void> _loadMyCity() async {
  final myUid = _uid;
  if (myUid == null) return;

  try {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(myUid)
        .get();

    final data = snap.data() ?? {};

    final city = (data['city'] ?? data['cityName'] ?? '').toString().trim();

    final code = (data['homeCountryCode'] ?? data['countryCode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    final country = (data['country'] ?? '').toString().trim().toLowerCase();

    if (!mounted) return;

    setState(() {
      _myCity = city;
      _myCountryCode = code;
      _myCountryName = country;
      _isPremium = data['isPremium'] == true || data['isMaster'] == true;
    });
  } catch (_) {}
}



  @override
  void initState() {
    super.initState();


    _loadMyCity();


    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _showBanner = false);
    });
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


  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }


  String _prettyCountry(String s) {
    final t = AppTexts.current;


    switch (s.trim().toLowerCase()) {
      case 'brasil':
        return t.get('country_brazil');
      case 'canada':
        return t.get('country_canada');
      case 'portugal':
        return t.get('country_portugal');
      default:
        final value = s.trim();
        if (value.isEmpty) return '--';
        if (value.length == 1) return value.toUpperCase();
        return value[0].toUpperCase() + value.substring(1);
    }
  }

String _countryNameFromCode(String code) {
  switch (code.trim().toLowerCase()) {
    case 'br':
      return 'brasil';
    case 'ca':
      return 'canada';
    case 'pt':
      return 'portugal';
    default:
      return code.trim().toLowerCase();
  }
}


  int _membersCount(Map<String, dynamic> data) {
    final m = data['members'];
    if (m is List) return m.length;


    final mc = data['membersCount'];
    if (mc is int) return mc;
    if (mc is num) return mc.toInt();
    return 0;
  }


  int _readMyUnread(Map<String, dynamic> data, String myUid) {
    final unreadRaw = data['unread'];


    if (unreadRaw is Map && unreadRaw.containsKey(myUid)) {
      final value = unreadRaw[myUid];
      if (value is int) return value;
      if (value is num) return value.toInt();
    }


    return 0;
  }


 

Query<Map<String, dynamic>> _query() {
  final ref = FirebaseFirestore.instance.collection('groups');

  final myCountry = _myCountryName.isNotEmpty
      ? _myCountryName
      : _countryNameFromCode(_myCountryCode);

  if (!_isPremium || _selectedCountry == 'all') {
    return ref
        .where('deleted', isEqualTo: false)
        .where('country', isEqualTo: myCountry)
        .orderBy('updatedAt', descending: true);
  }

  return ref
      .where('deleted', isEqualTo: false)
      .where('country', isEqualTo: _selectedCountry)
      .orderBy('updatedAt', descending: true);
}


  Future<void> _openCreate() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupPage()),
    );


    if (!mounted) return;
    if (ok == true) setState(() {});
  }


  Future<void> _openGroup({
    required String groupId,
    required String groupName,
    required bool isMember,
    required String inviteCode,
  }) async {
    final myUid = _uid;
    if (myUid == null) return;
    if (!mounted) return;


    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          groupId: groupId,
          groupName: groupName.isEmpty ? AppTexts.current.get('group') : groupName,
        ),
      ),
    );
  }


  Future<void> _showGroupActions({
    required String groupId,
    required Map<String, dynamic> data,
  }) async {
    final myUid = _uid;
    if (myUid == null) return;


    final adminsRaw = data['admins'];
    final admins = (adminsRaw is List)
        ? adminsRaw.map((e) => e.toString()).toList()
        : <String>[];


    final membersRaw = data['members'];
    final members = (membersRaw is List)
        ? membersRaw.map((e) => e.toString()).toList()
        : <String>[];


    final isAdmin = admins.contains(myUid);
    final isMember = members.contains(myUid);


    if (!isMember) return;


    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              if (isAdmin)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: _remdyBlue,
                  ),
                  title: const Text(
                    'Excluir grupo',
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _deleteGroupFromList(groupId: groupId);
                  },
                ),
              if (!isAdmin)
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: _remdyBlue,
                  ),
                  title: const Text(
                    'Sair do grupo',
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _leaveGroupFromList(groupId: groupId, data: data);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.close_rounded, color: _muted),
                title: const Text(
                  'Cancelar',
                  style: TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }


  Future<void> _deleteGroupFromList({required String groupId}) async {
    try {
      await FirebaseFirestore.instance.collection('groups').doc(groupId).set({
        'deleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));


      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grupo excluído ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao excluir grupo: $e')),
      );
    }
  }


  Future<void> _leaveGroupFromList({
    required String groupId,
    required Map<String, dynamic> data,
  }) async {
    final myUid = _uid;
    if (myUid == null) return;


    try {
      final unreadMap = Map<String, dynamic>.from(data['unread'] ?? {});
      unreadMap.remove(myUid);


      final currentMembers = (data['members'] is List)
          ? List<String>.from((data['members'] as List).map((e) => e.toString()))
          : <String>[];


      final currentAdmins = (data['admins'] is List)
          ? List<String>.from((data['admins'] as List).map((e) => e.toString()))
          : <String>[];


      currentMembers.remove(myUid);
      currentAdmins.remove(myUid);


      if (currentAdmins.isEmpty && currentMembers.isNotEmpty) {
        currentAdmins.add(currentMembers.first);
      }


      await FirebaseFirestore.instance.collection('groups').doc(groupId).set({
        'members': currentMembers,
        'admins': currentAdmins,
        'membersCount': currentMembers.length,
        'updatedAt': FieldValue.serverTimestamp(),
        'unread': unreadMap,
      }, SetOptions(merge: true));


      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você saiu do grupo ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao sair do grupo: $e')),
      );
    }
  }


  Widget _topBanner() {
    final t = AppTexts.current;


    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_remdyBlue, _logoBlue]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t.get('groups_banner_text'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _searchField() {
    final t = AppTexts.current;


    return TextField(
      controller: _searchC,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: t.get('search_groups_city_country'),
        prefixIcon: const Icon(Icons.search, color: _muted),
        suffixIcon: _searchC.text.trim().isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchC.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close, color: _muted),
              ),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _logoBlue),
        ),
      ),
    );
  }


  Widget _groupCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final t = AppTexts.current;
    final data = doc.data();


    final name = (data['name'] ?? t.get('group')).toString().trim();
    final bio = (data['bio'] ?? '').toString().trim();
    final country = (data['country'] ?? '').toString().trim();
    final city = (data['city'] ?? '').toString().trim();
    final inviteCode = (data['inviteCode'] ?? '').toString().trim();
    final members = _membersCount(data);


    final myUid = _uid;


    final membersList = (data['members'] is List)
        ? (data['members'] as List).map((e) => e.toString()).toList()
        : <String>[];


    final bool isMember = myUid != null && membersList.contains(myUid);


    int myUnread = 0;
    if (myUid != null) {
      myUnread = _readMyUnread(data, myUid);
    }
    final bool hasUnread = myUnread > 0;


    final avatarUrl = (data['avatarUrl'] ?? '').toString().trim();


    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openGroup(
        groupId: doc.id,
        groupName: name,
        isMember: isMember,
        inviteCode: inviteCode,
      ),
      onLongPress: isMember
          ? () => _showGroupActions(
                groupId: doc.id,
                data: data,
              )
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              height: 50,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name.isEmpty ? t.get('group') : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xFF1F2A44),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            myUnread > 99 ? '99+' : '$myUnread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${country.isEmpty ? '--' : _prettyCountry(country)} · ${city.isEmpty ? '--' : city}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$members ${members == 1 ? t.get('member') : t.get('members')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      bio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: isMember
                              ? const Color(0xFFF3F4F6)
                              : _remdyBlue,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isMember ? _border : _remdyBlue,
                          ),
                        ),
                        child: Text(
                          isMember ? t.get('open') : t.get('preview'),
                          style: TextStyle(
                            color: isMember ? _muted : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF9CA3AF),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;


    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          t.get('groups'),
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
      body: Column(
        children: [
          if (_showBanner)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: _topBanner(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _searchField(),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query().snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }


                if (snap.hasError) {
                  return Center(
                    child: Text(
                      '${t.get('error')}: ${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _muted),
                    ),
                  );
                }


                final allDocs = snap.data?.docs ?? [];
                final myUid = _uid;
                final query = _searchC.text.trim().toLowerCase();


                final filteredDocs = allDocs.where((doc) {
                  final data = doc.data();


                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final bio = (data['bio'] ?? '').toString().toLowerCase();
                  final city = (data['city'] ?? '').toString().toLowerCase();
                  final country =
                      (data['country'] ?? '').toString().toLowerCase();


                  if (query.isEmpty) return true;


                  return name.contains(query) ||
                      bio.contains(query) ||
                      city.contains(query) ||
                      country.contains(query);
                }).toList();


                final myGroups =
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                final cityGroups =
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                final otherGroups =
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];


                for (final doc in filteredDocs) {
                  final data = doc.data();


                  final membersList = (data['members'] is List)
                      ? (data['members'] as List)
                          .map((e) => e.toString())
                          .toList()
                      : <String>[];


                  final isMember =
                      myUid != null && membersList.contains(myUid);


                  final city = (data['city'] ?? '').toString().toLowerCase();
                  final myCity = _myCity.toLowerCase();


                  if (isMember) {
                    myGroups.add(doc);
                  } else if (city == myCity) {
                    cityGroups.add(doc);
                  } else {
                    otherGroups.add(doc);
                  }
                }


                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Text(
                      t.get('no_groups_found'),
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }


                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  children: [
                    if (myGroups.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10, top: 2),
                        child: Text(
                          t.get('my_groups'),
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      ...myGroups.map((doc) => _groupCard(context, doc)),
                    ],
                    if (cityGroups.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: 10,
                          top: myGroups.isNotEmpty ? 8 : 2,
                        ),
                        child: Text(
                          t.get('groups_in_your_city'),
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      ...cityGroups.map((doc) => _groupCard(context, doc)),
                    ],
                    if (otherGroups.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: 10,
                          top: myGroups.isNotEmpty ? 8 : 2,
                        ),
                        child: Text(
                          t.get('new_groups'),
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      ...otherGroups.map((doc) => _groupCard(context, doc)),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
