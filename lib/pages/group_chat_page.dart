import 'dart:async';
import 'dart:io';


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import '../l10n/app_texts.dart';


import 'group_info_page.dart';
import '../widget/audio_bubble.dart';
import '../widget/recording_button.dart';


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

  String _normalizeCountry(String value) {
  final v = value.trim().toLowerCase();


  if (v == 'ca' || v == 'canada') return 'ca';
  if (v == 'br' || v == 'brasil' || v == 'brazil') return 'br';
  if (v == 'pt' || v == 'portugal') return 'pt';


  return v;
}



  final _textC = TextEditingController();
  final _scrollC = ScrollController();
  final ImagePicker _picker = ImagePicker();

bool _searchMode = false;
String _searchText = '';
final TextEditingController _searchController = TextEditingController();

  Timer? _typingDebounce;


  String _loadedLocaleCode = '';


  String? get uid => FirebaseAuth.instance.currentUser?.uid;


  DocumentReference<Map<String, dynamic>> get _groupRef =>
      FirebaseFirestore.instance.collection('groups').doc(widget.groupId);


  CollectionReference<Map<String, dynamic>> get _msgsRef =>
      _groupRef.collection('messages');


  CollectionReference<Map<String, dynamic>> get _presenceRef =>
      _groupRef.collection('presence');


  bool _isAdmin = false;
  bool _loadingRole = true;
  bool _membershipChecked = false;
  bool _canSend = true;
  bool _isPremium = false;
  bool _isWorldGroup = false;
  String _myCountryCode = '';
  String _groupCountryCode = '';



  bool _booting = true;
  bool _didInitialRead = false;
  bool _isMember = false;
  bool _previewMode = false;


  Map<String, dynamic>? _groupData;


  final Map<String, Map<String, dynamic>> _userCache = {};
  final Set<String> _loadingUserIds = {};


  final List<_PendingAudioItem> _pendingAudios = [];
  final List<_PendingImageItem> _pendingImages = [];


  int _lastRenderedCount = 0;


  @override
  void initState() {
    super.initState();
    _textC.addListener(_onTextChanged);
    _bootstrap();
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
    _typingDebounce?.cancel();
    _setTyping(false);
    _setRecording(false);
    _textC.removeListener(_onTextChanged);
   _textC.dispose();
_searchController.dispose();
_scrollC.dispose();

    super.dispose();
  }


  Future<void> _resolveMembershipMode() async {
    if (_membershipChecked) return;
    _membershipChecked = true;


    final myUid = uid;
    if (myUid == null) {
      if (!mounted) return;
      setState(() {
        _isMember = false;
        _previewMode = true;
        _canSend = false;
      });
      return;
    }


    try {
      final data = _groupData ?? (await _groupRef.get()).data() ?? {};


      final membersRaw = data['members'];
      final members = (membersRaw is List)
          ? membersRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : <String>[];


      final alreadyMember = members.contains(myUid);


      if (!mounted) return;
      setState(() {
        _isMember = alreadyMember;
        _previewMode = !alreadyMember;
        _canSend = alreadyMember;
      });
    } catch (e) {
      debugPrint('Erro _resolveMembershipMode: $e');
      if (!mounted) return;
      setState(() {
        _isMember = false;
        _previewMode = true;
        _canSend = false;
      });
    }
  }


  Future<void> _joinGroup() async {
    final t = AppTexts.current;
    final myUid = uid;
    if (myUid == null) {
      _toast(t.get('group_login_to_join'));
      return;
    }
    if (_isWorldGroup && !_isPremium) {
      _toast(t.get('group_premium_other_country'));
      return;
    }


    try {
      final snap = await _groupRef.get();
      final data = snap.data() ?? {};


      final membersRaw = data['members'];
      final members = (membersRaw is List)
          ? membersRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : <String>[];


      final alreadyMember = members.contains(myUid);


      final unreadRaw = data['unread'];
      final Map<String, dynamic> unreadMap =
          unreadRaw is Map<String, dynamic>
              ? Map<String, dynamic>.from(unreadRaw)
              : unreadRaw is Map
                  ? unreadRaw.map((k, v) => MapEntry(k.toString(), v))
                  : <String, dynamic>{};


      unreadMap[myUid] = 0;


      await _groupRef.set({
        'members': FieldValue.arrayUnion([myUid]),
        'updatedAt': FieldValue.serverTimestamp(),
        'unread': unreadMap,
        if (!alreadyMember) 'membersCount': FieldValue.increment(1),
      }, SetOptions(merge: true));


      await _groupRef.collection('reads').doc(myUid).set({
        'lastReadAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));


      if (!mounted) return;
      setState(() {
        _isMember = true;
        _previewMode = false;
        _canSend = true;
        _didInitialRead = true;
      });


      await _markGroupAsRead();
    } catch (e) {
      _toast('${t.get('group_error_join_prefix')} $e');
    }
  }


  Future<void> _openGroup({
    required String groupId,
    required String groupName,
    required bool isMember,
  }) async {
    final t = AppTexts.current;
    if (!mounted) return;


    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          groupId: groupId,
          groupName: groupName.isEmpty ? t.get('group_generic') : groupName,
        ),
      ),
    );
  }


  Future<void> _loadGroupScope() async {
    final myUid = uid;
    if (myUid == null) return;


    try {
      final mySnap =
          await FirebaseFirestore.instance.collection('users').doc(myUid).get();
      final myData = mySnap.data() ?? {};


     final myCountry = _normalizeCountry(
  (myData['homeCountryCode'] ?? myData['countryCode'] ?? '').toString(),
);


final premium = myData['isPremium'] == true;


final groupData = _groupData ?? (await _groupRef.get()).data() ?? {};
final groupCountry = _normalizeCountry(
  (groupData['countryCode'] ?? groupData['country'] ?? '').toString(),
);



      if (!mounted) return;
      setState(() {
        _myCountryCode = myCountry;
        _groupCountryCode = groupCountry;
        _isPremium = premium;
        _isWorldGroup = myCountry.isNotEmpty &&
            groupCountry.isNotEmpty &&
            myCountry != groupCountry;
      });
    } catch (e) {
      debugPrint('Erro _loadGroupScope: $e');
    }
  }


  Future<void> _bootstrap() async {
    await _loadGroupHeaderAndRole();
    await _loadGroupScope();
    await _resolveMembershipMode();


    if (_isMember && !_didInitialRead) {
      _didInitialRead = true;
      await _markGroupAsRead();
    }


    if (!mounted) return;
    setState(() => _booting = false);
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

void _openSearch() {
  setState(() {
    _searchMode = true;
  });
}



  Future<void> _loadGroupHeaderAndRole() async {
    final myUid = uid;


    try {
      final g = await _groupRef.get();
      final gd = g.data() ?? {};
      _groupData = gd;


      if (myUid == null) {
        if (!mounted) return;
        setState(() {
          _isAdmin = false;
          _loadingRole = false;
        });
        return;
      }


      final ownerId = (gd['ownerId'] ?? '').toString().trim();
      final adminsRaw = gd['admins'];


      final admins = (adminsRaw is List)
          ? adminsRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
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
        _groupData = null;
        _isAdmin = false;
        _loadingRole = false;
      });
    }
  }


  Future<void> _ensureMemberIfAllowed() async {
    final t = AppTexts.current;
    if (_membershipChecked) return;
    _membershipChecked = true;


    final myUid = uid;
    if (myUid == null) {
      if (!mounted) return;
      setState(() => _canSend = false);
      return;
    }


    try {
      final data = _groupData ?? (await _groupRef.get()).data() ?? {};


      final membersRaw = data['members'];
      final members = (membersRaw is List)
          ? membersRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : <String>[];


      final alreadyMember = members.contains(myUid);


      if (alreadyMember) {
        if (!mounted) return;
        setState(() => _canSend = true);
        return;
      }


      final joinPolicy =
          (data['joinPolicy'] ?? 'open').toString().trim().toLowerCase();
      final isOpen = joinPolicy == 'open';


      if (!isOpen) {
        if (!mounted) return;
        setState(() => _canSend = false);
        _toast(t.get('group_not_member'));
        return;
      }


      final freshSnap = await _groupRef.get();
      final freshData = freshSnap.data() ?? {};
      final unreadMap = Map<String, dynamic>.from(freshData['unread'] ?? {});
      unreadMap[myUid] = 0;


      await _groupRef.set({
        'members': FieldValue.arrayUnion([myUid]),
        'updatedAt': FieldValue.serverTimestamp(),
        'unread': unreadMap,
        'membersCount': FieldValue.increment(1),
      }, SetOptions(merge: true));


      if (!mounted) return;
      setState(() => _canSend = true);
    } catch (e) {
      debugPrint('Erro _ensureMemberIfAllowed: $e');
      if (!mounted) return;
      setState(() => _canSend = false);
    }
  }


  Future<List<String>> _getMembers() async {
    final g = await _groupRef.get();
    final gd = g.data() ?? {};


    dynamic raw = gd['members'];
    raw ??= gd['participants'];
    raw ??= gd['memberIds'];


    final members = (raw is List)
        ? raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];


    return members;
  }


  Future<void> _markGroupAsRead() async {
    final myUid = uid;
    if (myUid == null) return;


    print('MARK GROUP AS READ => group=${widget.groupId} uid=$myUid');


    try {
      await _groupRef.collection('reads').doc(myUid).set({
        'lastReadAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));


      final snap = await _groupRef.get();
      final data = snap.data() ?? {};


      final unreadRaw = data['unread'];
      final Map<String, dynamic> unreadMap =
          unreadRaw is Map<String, dynamic>
              ? Map<String, dynamic>.from(unreadRaw)
              : unreadRaw is Map
                  ? unreadRaw.map((k, v) => MapEntry(k.toString(), v))
                  : <String, dynamic>{};


      unreadMap[myUid] = 0;


      await _groupRef.set({
        'unread': unreadMap,
      }, SetOptions(merge: true));


      final afterSnap = await _groupRef.get();
      print('AFTER MARK READ => ${afterSnap.data()?['unread']}');
    } catch (_) {}
  }


  Future<void> _preloadUsersFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final ids = <String>{};


    for (final doc in docs) {
      final d = doc.data();
      final senderId = (d['senderId'] ?? '').toString().trim();
      if (senderId.isNotEmpty && !_userCache.containsKey(senderId)) {
        ids.add(senderId);
      }
    }


    if (ids.isEmpty) return;


    for (final id in ids) {
      if (_loadingUserIds.contains(id)) continue;
      _loadingUserIds.add(id);


      FirebaseFirestore.instance.collection('users').doc(id).get().then((snap) {
        final data = snap.data() ?? {};
        _userCache[id] = data;
        _loadingUserIds.remove(id);
        if (mounted) setState(() {});
      }).catchError((_) {
        _loadingUserIds.remove(id);
      });
    }
  }


  Future<void> _setTyping(bool value) async {
    final myUid = uid;
    if (myUid == null) return;


    try {
      await _presenceRef.doc(myUid).set({
        'uid': myUid,
        'typing': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }


  Future<void> _setRecording(bool value) async {
    final myUid = uid;
    if (myUid == null) return;


    try {
      await _presenceRef.doc(myUid).set({
        'uid': myUid,
        'recording': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }


  void _onTextChanged() {
    final myUid = uid;
    if (myUid == null || !_canSend) return;


    final hasText = _textC.text.trim().isNotEmpty;


    setState(() {});
    _setTyping(hasText);


    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 1200), () {
      _setTyping(false);
    });
  }


  void _maybeAutoScroll(int newCount) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollC.hasClients) return;


      final shouldScroll = _scrollC.offset <= 120 || _lastRenderedCount == 0;
      _lastRenderedCount = newCount;


      if (!shouldScroll) return;


      _scrollC.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }


  Future<void> _send() async {
    final t = AppTexts.current;
    final myUid = uid;
    if (myUid == null || !_canSend) return;


    final text = _textC.text.trim();
    if (text.isEmpty) return;


    _textC.clear();
    _typingDebounce?.cancel();
    await _setTyping(false);


    try {
      final members = await _getMembers();
      if (!members.contains(myUid)) members.add(myUid);


      final batch = FirebaseFirestore.instance.batch();


      final msgRef = _msgsRef.doc();
      batch.set(msgRef, {
        'type': 'text',
        'text': text,
        'senderId': myUid,
        'createdAt': FieldValue.serverTimestamp(),
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
      });


      final groupSnap = await _groupRef.get();
      final groupData = groupSnap.data() ?? {};


      final unreadRaw = groupData['unread'];
      final Map<String, dynamic> unreadMap =
          unreadRaw is Map<String, dynamic>
              ? Map<String, dynamic>.from(unreadRaw)
              : unreadRaw is Map
                  ? unreadRaw.map((k, v) => MapEntry(k.toString(), v))
                  : <String, dynamic>{};


      unreadMap[myUid] = 0;


      for (final m in members) {
        if (m == myUid) continue;
        final current = unreadMap[m];
        final currentValue = current is num ? current.toInt() : 0;
        unreadMap[m] = currentValue + 1;
      }


      final Map<String, dynamic> patch = {
        'lastMessage': text,
        'lastSenderId': myUid,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'unread': unreadMap,
      };


      batch.set(_groupRef, patch, SetOptions(merge: true));


      final readRef = _groupRef.collection('reads').doc(myUid);
      batch.set(
        readRef,
        {'lastReadAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );


      await batch.commit();
      final afterSnap = await _groupRef.get();
      print('GROUP AFTER SEND => ${afterSnap.data()}');
    } catch (e) {
      _toast('${t.get('group_error_send_prefix')} $e');
    }
  }


  Future<String> _uploadGroupAudioToStorage({
    required String groupId,
    required String myUid,
    required String localPath,
  }) async {
    final t = AppTexts.current;
    final file = File(localPath);


    if (!await file.exists()) {
      throw Exception('${t.get('group_audio_file_not_found_prefix')} $localPath');
    }


    final size = await file.length();
    if (size <= 0) {
      throw Exception('${t.get('group_audio_file_empty_prefix')} $localPath');
    }


    final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}_$myUid.m4a';


    final ref = FirebaseStorage.instance
        .ref()
        .child('groups')
        .child(groupId)
        .child('audio')
        .child(myUid)
        .child(fileName);


    final metadata = SettableMetadata(contentType: 'audio/mp4');


    await ref.putFile(file, metadata);
    return await ref.getDownloadURL();
  }


  Future<String> _uploadGroupImageToStorage({
    required String groupId,
    required String myUid,
    required String localPath,
  }) async {
    final t = AppTexts.current;
    final file = File(localPath);


    if (!await file.exists()) {
      throw Exception('${t.get('group_image_not_found_prefix')} $localPath');
    }


    final size = await file.length();
    if (size <= 0) {
      throw Exception('${t.get('group_image_empty_prefix')} $localPath');
    }


    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}_$myUid.jpg';


    final ref = FirebaseStorage.instance
        .ref()
        .child('groups')
        .child(groupId)
        .child('images')
        .child(myUid)
        .child(fileName);


    final metadata = SettableMetadata(contentType: 'image/jpeg');


    await ref.putFile(file, metadata);
    return await ref.getDownloadURL();
  }


  Future<void> _sendGroupAudioMessage(String localPath) async {
    final t = AppTexts.current;
    final myUid = uid;
    if (myUid == null || !_canSend) return;


    final pendingId = DateTime.now().microsecondsSinceEpoch.toString();


    if (mounted) {
      setState(() {
        _pendingAudios.insert(
          0,
          _PendingAudioItem(
            localId: pendingId,
            senderId: myUid,
            createdAt: DateTime.now(),
          ),
        );
      });
    }


    try {
      final members = await _getMembers();
      if (!members.contains(myUid)) members.add(myUid);


      final tmp = AudioPlayer();
      Duration? dur;
      try {
        await tmp.setFilePath(localPath);
        dur = tmp.duration;
      } catch (_) {}
      await tmp.dispose();


      final audioUrl = await _uploadGroupAudioToStorage(
        groupId: widget.groupId,
        myUid: myUid,
        localPath: localPath,
      );


      final batch = FirebaseFirestore.instance.batch();


      final msgRef = _msgsRef.doc();
      batch.set(msgRef, {
        'type': 'audio',
        'text': '🎤 Áudio',
        'audioUrl': audioUrl,
        'durationMs': dur?.inMilliseconds ?? 0,
        'senderId': myUid,
        'createdAt': FieldValue.serverTimestamp(),
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
      });


      final groupSnap = await _groupRef.get();
      final groupData = groupSnap.data() ?? {};


      final unreadRaw = groupData['unread'];
      final Map<String, dynamic> unreadMap =
          unreadRaw is Map<String, dynamic>
              ? Map<String, dynamic>.from(unreadRaw)
              : unreadRaw is Map
                  ? unreadRaw.map((k, v) => MapEntry(k.toString(), v))
                  : <String, dynamic>{};


      unreadMap[myUid] = 0;


      for (final m in members) {
        if (m == myUid) continue;
        final current = unreadMap[m];
        final currentValue = current is num ? current.toInt() : 0;
        unreadMap[m] = currentValue + 1;
      }


      final Map<String, dynamic> patch = {
        'lastMessage': '🎤 Áudio',
        'lastSenderId': myUid,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'unread': unreadMap,
      };


      batch.set(_groupRef, patch, SetOptions(merge: true));


      final readRef = _groupRef.collection('reads').doc(myUid);
      batch.set(
        readRef,
        {'lastReadAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );


      await batch.commit();
      final afterSnap = await _groupRef.get();
      print('GROUP AFTER SEND => ${afterSnap.data()}');


      if (mounted) {
        setState(() {
          _pendingAudios.removeWhere((e) => e.localId == pendingId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pendingAudios.removeWhere((e) => e.localId == pendingId);
        });
      }
      _toast('${t.get('group_error_send_audio_prefix')} $e');
    }
  }


  Future<void> _sendGroupImageMessage(String localPath) async {
    final t = AppTexts.current;
    final myUid = uid;
    if (myUid == null || !_canSend) return;


    final pendingId = DateTime.now().microsecondsSinceEpoch.toString();


    if (mounted) {
      setState(() {
        _pendingImages.insert(
          0,
          _PendingImageItem(
            localId: pendingId,
            senderId: myUid,
            createdAt: DateTime.now(),
            localPath: localPath,
          ),
        );
      });
    }


    try {
      final members = await _getMembers();
      if (!members.contains(myUid)) members.add(myUid);


      final imageUrl = await _uploadGroupImageToStorage(
        groupId: widget.groupId,
        myUid: myUid,
        localPath: localPath,
      );


      final batch = FirebaseFirestore.instance.batch();


      final msgRef = _msgsRef.doc();
      batch.set(msgRef, {
        'type': 'image',
        'text': '',
        'imageUrl': imageUrl,
        'senderId': myUid,
        'createdAt': FieldValue.serverTimestamp(),
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
      });


      final groupSnap = await _groupRef.get();
      final groupData = groupSnap.data() ?? {};
      final unreadMap = Map<String, dynamic>.from(groupData['unread'] ?? {});


      unreadMap[myUid] = 0;


      for (final m in members) {
        if (m == myUid) continue;
        final current = unreadMap[m];
        final currentValue = current is num ? current.toInt() : 0;
        unreadMap[m] = currentValue + 1;
      }


      final Map<String, dynamic> patch = {
        'lastMessage': '📷 Foto',
        'lastSenderId': myUid,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'unread': unreadMap,
      };


      batch.set(_groupRef, patch, SetOptions(merge: true));


      final readRef = _groupRef.collection('reads').doc(myUid);
      batch.set(
        readRef,
        {'lastReadAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );


      await batch.commit();
      final afterSnap = await _groupRef.get();
      print('GROUP AFTER SEND => ${afterSnap.data()}');


      if (mounted) {
        setState(() {
          _pendingImages.removeWhere((e) => e.localId == pendingId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pendingImages.removeWhere((e) => e.localId == pendingId);
        });
      }
      _toast('${t.get('group_error_send_image_prefix')} $e');
    }
  }


  Future<void> _pickAndSendImage(ImageSource source) async {
    final t = AppTexts.current;
    if (!_canSend) return;


    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );


      if (file == null) return;


      await _sendGroupImageMessage(file.path);
    } catch (e) {
      _toast('${t.get('group_error_pick_image_prefix')} $e');
    }
  }


  void _openPlusMenu() {
    final t = AppTexts.current;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(t.get('group_gallery')),
              onTap: () async {
                Navigator.pop(context);
                await _pickAndSendImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(t.get('group_camera')),
              onTap: () async {
                Navigator.pop(context);
                await _pickAndSendImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _deleteForMe({
    required String messageId,
  }) async {
    final t = AppTexts.current;
    final myUid = uid;
    if (myUid == null) return;


    try {
      await _msgsRef.doc(messageId).set({
        'deletedFor': FieldValue.arrayUnion([myUid]),
      }, SetOptions(merge: true));
    } catch (e) {
      _toast(t.get('group_error_delete_message'));
    }
  }


  Future<void> _hardDeleteMessage({
    required String messageId,
  }) async {
    final t = AppTexts.current;
    try {
      final snap = await _msgsRef.doc(messageId).get();
      final data = snap.data() ?? {};


      final type = (data['type'] ?? 'text').toString().trim();
      final audioUrl = (data['audioUrl'] ?? '').toString().trim();
      final imageUrl = (data['imageUrl'] ?? '').toString().trim();


      if (type == 'audio' && audioUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(audioUrl).delete();
        } catch (_) {}
      }


      if (type == 'image' && imageUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(imageUrl).delete();
        } catch (_) {}
      }


      await _msgsRef.doc(messageId).delete();
    } catch (e) {
      _toast('${t.get('group_error_delete_message_prefix')} $e');
    }
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
    final t = AppTexts.current;
    if (_loadingRole) return;
    final canDelete = isMyMessage || _isAdmin;


    if (!canDelete) return;


    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(t.get('group_delete_for_me')),
              onTap: () async {
                Navigator.pop(context);
                await _deleteForMe(messageId: messageId);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_forever_rounded, color: _remdyBlue),
              title: Text(
                isMyMessage
                    ? t.get('group_delete_for_all')
                    : t.get('group_delete_admin'),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _hardDeleteMessage(messageId: messageId);
              },
            ),
          ],
        ),
      ),
    );
  }


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


  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }


  String _formatTimeFromDate(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }


  String _formatDayLabel(Timestamp? ts) {
    final t = AppTexts.current;
    if (ts == null) return t.get('group_today');
    final d = ts.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;


    if (diff == 0) return t.get('group_today');
    if (diff == 1) return t.get('group_yesterday');


    const months = [
      '',
      'jan',
      'fev',
      'mar',
      'abr',
      'mai',
      'jun',
      'jul',
      'ago',
      'set',
      'out',
      'nov',
      'dez',
    ];
    return '${d.day} ${months[d.month]}';
  }


  bool _shouldShowDateHeader(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int index,
  ) {
    if (index == docs.length - 1) return true;


    final currentTs = docs[index].data()['createdAt'] as Timestamp?;
    final nextTs = docs[index + 1].data()['createdAt'] as Timestamp?;


    if (currentTs == null || nextTs == null) return false;


    final a = currentTs.toDate();
    final b = nextTs.toDate();


    return a.year != b.year || a.month != b.month || a.day != b.day;
  }


  String _presenceLabel(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final t = AppTexts.current;
    final myUid = uid;
    if (myUid == null) return '';


    final now = DateTime.now();


    final List<String> typingNames = [];
    final List<String> recordingNames = [];


    for (final doc in docs) {
      final d = doc.data();
      final otherUid = (d['uid'] ?? '').toString().trim();
      if (otherUid.isEmpty || otherUid == myUid) continue;


      final updatedAt = d['updatedAt'];
      DateTime? when;
      if (updatedAt is Timestamp) {
        when = updatedAt.toDate();
      }


      if (when != null && now.difference(when).inSeconds > 6) {
        continue;
      }


      final typing = d['typing'] == true;
      final recording = d['recording'] == true;


      final userData = _userCache[otherUid];
      final rawName =
          (userData?['name'] ?? t.get('group_someone')).toString().trim();
      final name = rawName.isEmpty ? t.get('group_someone') : rawName;


      if (recording) {
        recordingNames.add(name);
        continue;
      }


      if (typing) {
        typingNames.add(name);
      }
    }


    String buildLabel(
      List<String> names,
      String singleAction,
      String pluralAction,
    ) {
      if (names.isEmpty) return '';
      if (names.length == 1) return '${names[0]} $singleAction';
      if (names.length == 2) return '${names[0]} e ${names[1]} $pluralAction';
      return '${names.length} ${t.get('group_people')} $pluralAction';
    }


    final recordingLabel = buildLabel(
      recordingNames,
      t.get('group_is_recording_audio'),
      t.get('group_are_recording_audio'),
    );


    if (recordingLabel.isNotEmpty) return recordingLabel;


    final typingLabel = buildLabel(
      typingNames,
      t.get('group_is_typing'),
      t.get('group_are_typing'),
    );


    return typingLabel;
  }


  Widget _buildPreviewBottomBar() {
    final t = AppTexts.current;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  t.get('group_back'),
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _joinGroup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _remdyBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  t.get('group_join_group'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
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
    final headerName =
        ((_groupData?['name'] ?? widget.groupName).toString().trim()).isEmpty
            ? widget.groupName
            : (_groupData?['name'] ?? widget.groupName).toString().trim();


    return Scaffold(
      backgroundColor: _bg,
appBar: AppBar(
  backgroundColor: _bg,
  surfaceTintColor: _bg,
  scrolledUnderElevation: 0,
  elevation: 0,
  iconTheme: const IconThemeData(color: _muted),
  centerTitle: true,
  actions: [
    _searchMode
        ? IconButton(
            onPressed: () {
              setState(() {
                _searchMode = false;
                _searchText = '';
                _searchController.clear();
              });
            },
            icon: const Icon(Icons.close, color: _muted),
          )
        : IconButton(
            onPressed: _openSearch,
            icon: const Icon(Icons.search, color: _muted),
          ),
  ],
  title: _searchMode
      ? TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: (value) {
            setState(() {
              _searchText = value.trim().toLowerCase();
            });
          },
     decoration: InputDecoration(
  hintText: t.get('group_search_messages'),
  border: InputBorder.none,
),

          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        )
      : InkWell(
          onTap: _openInfo,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _groupAvatarFromData(_groupData),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    headerName,
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
        ),
),

      body: _booting
          ? const SizedBox.shrink()
          : Column(
              children: [
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _presenceRef.snapshots(),
                  builder: (context, snap) {
                    final docs = snap.data?.docs ?? [];






                    final label = _presenceLabel(docs);


                    if (label.isEmpty) return const SizedBox.shrink();


                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _msgsRef
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snap) {
                     

final allDocs = snap.data?.docs ?? [];


final docs = _searchText.isEmpty
    ? allDocs
    : allDocs.where((doc) {
        final data = doc.data();
        final text = (data['text'] ?? '').toString().toLowerCase();
        return text.contains(_searchText);
      }).toList();


WidgetsBinding.instance.addPostFrameCallback((_) {
  _preloadUsersFromDocs(docs);
  _maybeAutoScroll(
    docs.length +
        _pendingAudios.length +
        _pendingImages.length,
  );
});


final totalCount = docs.length +
    _pendingAudios.length +
    _pendingImages.length;



                      if (totalCount == 0) {
  return Center(
    child: Text(
      _searchText.isNotEmpty
          ? t.get('group_no_search_results')
          : t.get('group_no_messages_yet'),
      style: const TextStyle(
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
                        itemCount: totalCount,
                        itemBuilder: (context, i) {
                          if (i < _pendingImages.length) {
                            final pending = _pendingImages[i];
                            final isMe = pending.senderId == uid;


                            return _ImageSendingBubble(
                              isMe: isMe,
                              timeText: _formatTimeFromDate(pending.createdAt),
                              localPath: pending.localPath,
                            );
                          }


                          final afterPendingImages = i - _pendingImages.length;


                          if (afterPendingImages < _pendingAudios.length) {
                            final pending = _pendingAudios[afterPendingImages];
                            final isMe = pending.senderId == uid;


                            return _AudioSendingBubble(
                              isMe: isMe,
                              timeText: _formatTimeFromDate(pending.createdAt),
                            );
                          }


                          final realIndex =
                              afterPendingImages - _pendingAudios.length;
                          final doc = docs[realIndex];
                          final d = doc.data();


                          final senderId =
                              (d['senderId'] ?? '').toString().trim();
                          final isMe = (uid != null && senderId == uid);


                          final type = (d['type'] ?? 'text').toString().trim();
                          final deleted = d['deleted'] == true;


                          final deletedFor = (d['deletedFor'] ?? []) as List;
                          final hiddenForMe =
                              uid != null && deletedFor.contains(uid);


                          if (hiddenForMe) {
                            return const SizedBox.shrink();
                          }


                          final deletedText =
                              (d['deletedText'] ?? '').toString().trim();
                          final createdAt = d['createdAt'] as Timestamp?;


                          Widget bubbleWidget;


                          if (deleted) {
                            final text = deletedText.isNotEmpty
                                ? deletedText
                                : t.get('group_message_deleted_by_admin');


                            bubbleWidget = _Bubble(
                              text: text,
                              isMe: isMe,
                              isDeleted: true,
                              timeText: _formatTime(createdAt),
                            );
                          } else if (type == 'audio') {
  final url = (d['audioUrl'] ?? '').toString();
  final raw = d['durationMs'] ?? 0;
  final durationMs = raw is int
      ? raw
      : (raw is num ? raw.toInt() : 0);


  if (_previewMode) {
    bubbleWidget = _PreviewAudioBubble(
      isMe: isMe,
      durationMs: durationMs,
      timeText: _formatTime(createdAt),
    );
  } else {
    bubbleWidget = AudioBubble(
      key: ValueKey('audio_${doc.id}_$url'),
      messageId: doc.id,
      audioUrl: url,
      isMe: isMe,
      durationMs: durationMs,
      timeText: _formatTime(createdAt),
    );
  }
}
 else if (type == 'image') {
                            final imageUrl = (d['imageUrl'] ?? '').toString();


                            bubbleWidget = _ImageBubble(
                              imageUrl: imageUrl,
                              isMe: isMe,
                              timeText: _formatTime(createdAt),
                            );
                          } else {
                            final text = (d['text'] ?? '').toString();
                            bubbleWidget = _Bubble(
                              text: text,
                              isMe: isMe,
                              isDeleted: false,
                              timeText: _formatTime(createdAt),
                            );
                          }


                          final userData =
                              senderId.isNotEmpty ? _userCache[senderId] : null;


                          final bubble = senderId.isEmpty
                              ? bubbleWidget
                              : MessageRow(
                                  senderUid: senderId,
                                  isMe: isMe,
                                  bubble: bubbleWidget,
                                  userData: userData,
                                );


                          final showDate =
                              _shouldShowDateHeader(docs, realIndex);


                          return Column(
                            children: [
                              if (showDate)
                                _DateHeader(label: _formatDayLabel(createdAt)),
                              GestureDetector(
                                onLongPress: () async {
                                  final canDelete = isMe || _isAdmin;
                                  if (!canDelete) return;
                                  await _openActions(
                                    messageId: doc.id,
                                    isMyMessage: isMe,
                                  );
                                },
                                child: bubble,
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                _previewMode
                    ? _buildPreviewBottomBar()
                    : SafeArea(
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              top: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  child: TextField(
                                    controller: _textC,
                                    enabled: uid != null && _canSend,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _send(),
                                    decoration: InputDecoration(
                                      hintText: uid == null
                                          ? t.get('group_login_to_chat')
                                          : !_canSend
                                              ? t.get(
                                                  'group_cannot_send_in_this_group',
                                                )
                                              : t.get('group_type_message'),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap:
                                    (uid == null || !_canSend) ? null : _openPlusMenu,
                                borderRadius: BorderRadius.circular(999),
                                child: Opacity(
                                  opacity: (uid == null || !_canSend) ? 0.5 : 1,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: const Color(0xFFE5E7EB),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.add,
                                      color: Color(0xFF6B7280),
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _textC.text.trim().isEmpty
                                  ? RecordingButton(
                                      onRecordStart: () async {
                                        await _setRecording(true);
                                      },
                                      onRecordStop: () async {
                                        await _setRecording(false);
                                      },
                                      onRecorded: (path) async {
                                        if (path == null) return;
                                        await _sendGroupAudioMessage(path);
                                      },
                                    )
                                  : InkWell(
                                      onTap: _send,
                                      borderRadius: BorderRadius.circular(999),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: _remdyBlue,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: const Icon(
                                          Icons.send,
                                          color: Colors.white,
                                          size: 20,
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


class _PendingAudioItem {
  final String localId;
  final String senderId;
  final DateTime createdAt;


  _PendingAudioItem({
    required this.localId,
    required this.senderId,
    required this.createdAt,
  });
}


class _PendingImageItem {
  final String localId;
  final String senderId;
  final DateTime createdAt;
  final String localPath;


  _PendingImageItem({
    required this.localId,
    required this.senderId,
    required this.createdAt,
    required this.localPath,
  });
}


class _AudioSendingBubble extends StatelessWidget {
  final bool isMe;
  final String timeText;


  const _AudioSendingBubble({
    required this.isMe,
    required this.timeText,
  });


  static const Color _remdyBlue = Color(0xFF313A5F);


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final bg = isMe ? _remdyBlue : Colors.white;
    final fg = isMe ? Colors.white : const Color(0xFF111827);
    final timeColor = isMe ? Colors.white70 : const Color(0xFF6B7280);


    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        constraints: const BoxConstraints(maxWidth: 290),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMe ? _remdyBlue : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isMe ? Colors.white : _remdyBlue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    t.get('group_sending_audio'),
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    timeText,
                    style: TextStyle(
                      color: timeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _ImageSendingBubble extends StatelessWidget {
  final bool isMe;
  final String timeText;
  final String localPath;


  const _ImageSendingBubble({
    required this.isMe,
    required this.timeText,
    required this.localPath,
  });


  static const Color _remdyBlue = Color(0xFF313A5F);


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final borderColor = isMe ? _remdyBlue : const Color(0xFFE5E7EB);


    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color: isMe ? _remdyBlue : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(localPath),
                width: 200,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isMe ? Colors.white : _remdyBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  t.get('group_sending_image'),
                  style: TextStyle(
                    color: isMe ? Colors.white : const Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              timeText,
              style: TextStyle(
                color: isMe ? Colors.white70 : const Color(0xFF6B7280),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _ImageBubble extends StatelessWidget {
  final String imageUrl;
  final bool isMe;
  final String timeText;


  const _ImageBubble({
    required this.imageUrl,
    required this.isMe,
    required this.timeText,
  });


  static const Color _remdyBlue = Color(0xFF313A5F);


  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _FullScreenImagePage(imageUrl: imageUrl),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(maxWidth: 240),
          decoration: BoxDecoration(
            color: isMe ? _remdyBlue : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isMe ? _remdyBlue : const Color(0xFFE5E7EB),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 200,
                    height: 200,
                    color: const Color(0xFFF1F5F9),
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                timeText,
                style: TextStyle(
                  color: isMe ? Colors.white70 : const Color(0xFF6B7280),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _FullScreenImagePage extends StatelessWidget {
  final String imageUrl;


  const _FullScreenImagePage({
    required this.imageUrl,
  });


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(


        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}


class _DateHeader extends StatelessWidget {
  final String label;


  const _DateHeader({required this.label});


  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
      ),
    );
  }
}


class _Bubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final bool isDeleted;
  final String timeText;


  const _Bubble({
    required this.text,
    required this.isMe,
    required this.isDeleted,
    required this.timeText,
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


    final timeStyle = TextStyle(
      color: isMe ? Colors.white70 : const Color(0xFF6B7280),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );


    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        constraints: const BoxConstraints(maxWidth: 290),
        decoration: BoxDecoration(
          color: isMe ? _remdyBlue : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMe ? _remdyBlue : const Color(0xFFE5E7EB),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(text, style: style),
            if (timeText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(timeText, style: timeStyle),
            ],
          ],
        ),
      ),
    );
  }
}


class MessageRow extends StatelessWidget {
  final String senderUid;
  final bool isMe;
  final Widget bubble;
  final Map<String, dynamic>? userData;


  const MessageRow({
    super.key,
    required this.senderUid,
    required this.isMe,
    required this.bubble,
    required this.userData,
  });


  static const Color _muted = Color(0xFF6B7280);


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final safeUid = senderUid.trim();
    if (safeUid.isEmpty) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      );
    }


    if (isMe) {
      return Align(
        alignment: Alignment.centerRight,
        child: bubble,
      );
    }


    final photoUrl = (userData?['photoUrl'] ?? '').toString().trim();
    final avatarUrl = (userData?['avatarUrl'] ?? '').toString().trim();
    final pic = photoUrl.isNotEmpty ? photoUrl : avatarUrl;
    final name = (userData?['name'] ?? t.get('group_user')).toString().trim();
    final role = (userData?['role'] ?? '').toString().trim();


    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 22,
            height: 22,
            color: const Color(0xFFF1F5F9),
            child: pic.isNotEmpty
                ? Image.network(
                    pic,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.person, size: 14, color: _muted),
                  )
                : const Icon(Icons.person, size: 14, color: _muted),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name.isEmpty ? t.get('group_user') : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (role.toLowerCase() == 'admin') ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.shield_outlined,
                        size: 12,
                        color: _muted,
                      ),
                    ],
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: bubble,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
class _PreviewAudioBubble extends StatelessWidget {
  final bool isMe;
  final int durationMs;
  final String timeText;


  const _PreviewAudioBubble({
    required this.isMe,
    required this.durationMs,
    required this.timeText,
  });


  static const Color _remdyBlue = Color(0xFF313A5F);


  String _formatDuration(int ms) {
    final totalSeconds = (ms / 1000).floor();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }


  @override
  Widget build(BuildContext context) {
    final bg = isMe ? _remdyBlue : Colors.white;
    final fg = isMe ? Colors.white : const Color(0xFF111827);
    final muted = isMe ? Colors.white70 : const Color(0xFF6B7280);


    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        constraints: const BoxConstraints(maxWidth: 290),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMe ? _remdyBlue : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDuration(durationMs),
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    timeText,
                    style: TextStyle(
                      color: muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
