import 'dart:async';
import 'dart:io';


import 'package:audio_session/audio_session.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:socialchat_mvp/pages/Premium_page.dart';
import 'package:socialchat_mvp/pages/public_profile_page.dart';
import 'package:socialchat_mvp/services/audio_playback_controller.dart';
import 'package:socialchat_mvp/services/block_service.dart';
import 'package:socialchat_mvp/widget/audio_bubble.dart';


import '../l10n/app_texts.dart';
import '../services/voice_service.dart';
import '../widget/online_dot.dart';
import '../widget/recording_button.dart';


class ChatPage extends StatefulWidget {
  final String conversationId;
  final String otherUid;
  final String otherName;


  const ChatPage({
    super.key,
    required this.conversationId,
    required this.otherUid,
    required this.otherName,
  });


  @override
  State<ChatPage> createState() => _ChatPageState();
}


class _ChatPageState extends State<ChatPage> {
  final _textC = TextEditingController();
  final _scrollC = ScrollController();
  final ImagePicker _picker = ImagePicker();
  bool _searchMode = false;
String _searchText = '';
final TextEditingController _searchController = TextEditingController();




  final db = FirebaseFirestore.instance;
  final myUid = FirebaseAuth.instance.currentUser!.uid;


  bool _sending = false;
  DateTime? _lastSentAt;
  static const int _cooldownMs = 900;


  String _loadedLocaleCode = '';


  // anti-flicker
  int _lastMsgCount = 0;


  Timer? _typingDebounce;


  String? _replyToMessageId;
  String _replyToText = '';
  String _replyToType = 'text';
  bool _replyToIsMe = false;
  double _dragDx = 0;
  String _replyToImageUrl = '';


  // ===== Pendências locais =====
  final List<_PendingAudioItem> _pendingAudios = [];
  final List<_PendingImageItem> _pendingImages = [];


  void _handleReplyFromMessage(Map<String, dynamic> d, String fallbackType) {
    final t = AppTexts.current;


    final senderId = (d['senderId'] ?? '').toString();
    final isMe = senderId == myUid;


    final type = (d['type'] ?? fallbackType).toString();


    String preview = '';
    String imageUrl = '';


    if (type == 'text') {
      preview = (d['text'] ?? '').toString().trim();
    } else if (type == 'audio') {
      preview = t.get('chat_audio_label');
    } else if (type == 'image') {
      preview = t.get('chat_photo_label');
      imageUrl = (d['imageUrl'] ?? '').toString();
    } else {
      preview = t.get('chat_message_generic');
    }


    final messageId = (d['id'] ?? '').toString();
    if (messageId.isEmpty) return;


    _startReply(
      messageId: messageId,
      text: preview.isEmpty ? t.get('chat_message_generic') : preview,
      type: type,
      isMe: isMe,
      imageUrl: imageUrl,
    );
  }

  
String _messagePreviewText(Map<String, dynamic> d, String fallbackType) {
  final t = AppTexts.current;
  final type = (d['type'] ?? fallbackType).toString();

  if (d['deleted'] == true) {
    return t.get('chat_message_deleted');
  }

  if (type == 'audio') return t.get('chat_audio_label');
  if (type == 'image') return t.get('chat_photo_label');

  final text = (d['text'] ?? '').toString().trim();
  if (text.isNotEmpty) return text;

  return t.get('chat_message_generic');
}



  CollectionReference<Map<String, dynamic>> get _presenceRef =>
      convDoc.collection('presence');


  // ===== Premium =====
bool _isPremium = false;
bool _isMaster = false;

bool _isPremiumPaid = false;
bool _hasActiveTimePremium = false;
DateTime? _premiumUntil;



  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _premiumSub;


  // ===== Escopo (país vs mundo) =====
  bool _isWorldChat = false;
  String _myCountryCode = '';
  String _otherCountryCode = '';


  // ===== Tempo trial (MUNDO) =====
  Timer? _usageTimer;
int _dailySecondsUsed = 0;
int _dailyLimitSeconds = 3600;
bool _limitReached = false;
DateTime? _lastUsageWriteAt;
static const int _freeWorldLimitSeconds = 3600;



  final ValueNotifier<int> _remainingVN = ValueNotifier<int>(0);


  DocumentReference<Map<String, dynamic>> get convDoc =>
      db.collection('conversations').doc(widget.conversationId);


  CollectionReference<Map<String, dynamic>> get msgsCol =>
      convDoc.collection('messages');


  DocumentReference<Map<String, dynamic>> get myUserDoc =>
      db.collection('users').doc(myUid);


  DocumentReference<Map<String, dynamic>> get otherUserDoc =>
      db.collection('users').doc(widget.otherUid);


  late final Stream<QuerySnapshot<Map<String, dynamic>>> _msgsStream;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _otherUserStream;
  late final Stream<bool> _blockedStream;


  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _msgsSub;


  // =======================
  // Remdy UI (só visual)
  // =======================
  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _card = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);


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


  String _formatSeconds(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }


  int get _remainingSeconds =>
      (_dailyLimitSeconds - _dailySecondsUsed).clamp(0, _dailyLimitSeconds);
      bool get _canUseWorldChat {
  return !_isWorldChat || _isPremium;
}



bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}



 void _warn(String msg) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(12),
    ),
  );
}

  void _startReply({
    required String messageId,
    required String text,
    required String type,
    required bool isMe,
    String imageUrl = '',
  }) {
    setState(() {
      _replyToMessageId = messageId;
      _replyToText = text;
      _replyToType = type;
      _replyToIsMe = isMe;
      _replyToImageUrl = imageUrl;
    });
  }


  void _cancelReply() {
    setState(() {
      _replyToMessageId = null;
      _replyToText = '';
      _replyToType = 'text';
      _replyToIsMe = false;
      _replyToImageUrl = '';
    });
  }


  bool _containsLink(String text) {
    final t = text.toLowerCase();
    return t.contains('http://') ||
        t.contains('https://') ||
        t.contains('www.') ||
        t.contains('.com') ||
        t.contains('.net') ||
        t.contains('.ca') ||
        t.contains('.br');
  }


  bool _containsPhone(String text) {
    final t = text.trim();
    final intl = RegExp(r'\+\s?\d{1,3}');
    final generic = RegExp(r'\d[\d\s().-]{7,}\d');
    return intl.hasMatch(t) || generic.hasMatch(t);
  }


  String _makePendingId() {
    return '${DateTime.now().microsecondsSinceEpoch}_${myUid}_${widget.conversationId}';
  }


  void _addPendingAudio({
    required String pendingId,
    required String localPath,
  }) {
    if (!mounted) return;
    setState(() {
      _pendingAudios.insert(
        0,
        _PendingAudioItem(
          pendingId: pendingId,
          localPath: localPath,
          createdAt: DateTime.now(),
        ),
      );
    });
  }


  void _removePendingAudio(String pendingId) {
    if (!mounted) return;
    setState(() {
      _pendingAudios.removeWhere((e) => e.pendingId == pendingId);
    });
  }


  void _addPendingImage({
    required String pendingId,
    required String localPath,
  }) {
    if (!mounted) return;
    setState(() {
      _pendingImages.insert(
        0,
        _PendingImageItem(
          pendingId: pendingId,
          localPath: localPath,
          createdAt: DateTime.now(),
        ),
      );
    });
  }


  void _removePendingImage(String pendingId) {
    if (!mounted) return;
    setState(() {
      _pendingImages.removeWhere((e) => e.pendingId == pendingId);
    });
  }


  List<_PendingChatListItem> _buildPendingItems() {
    final items = <_PendingChatListItem>[
      ..._pendingAudios.map(
        (e) => _PendingChatListItem.audio(
          pendingId: e.pendingId,
          createdAt: e.createdAt,
        ),
      ),
      ..._pendingImages.map(
        (e) => _PendingChatListItem.image(
          pendingId: e.pendingId,
          createdAt: e.createdAt,
        ),
      ),
    ];


    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }


  Future<void> _disableForegroundPushUI() async {
    try {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
    } catch (_) {}
  }


 void _listenPremium() {
  _premiumSub?.cancel();

  _premiumSub = myUserDoc.snapshots().listen((snap) {
    final data = snap.data() ?? {};

    final paid = (data['isPremium'] ?? false) == true;
    final master = data['isMaster'] == true;


    final untilRaw = data['premiumUntil'];
    DateTime? until;
    if (untilRaw is Timestamp) until = untilRaw.toDate();

    final timePremiumActive =
        (until != null) && until.isAfter(DateTime.now());

    _isPremiumPaid = paid;
    _hasActiveTimePremium = timePremiumActive;
    _premiumUntil = until;

   
final active = _isPremiumPaid || master;



    if (!mounted) return;
    setState(() {
    
_isPremium = active;
_isMaster = master;

    });

    _applyTimerRules();
  });
}


  Future<void> _loadChatScope() async {
  try {
    final mySnap = await myUserDoc.get();

    final otherSnap = await otherUserDoc.get();

    final publicOtherSnap = await db
        .collection('publicUsers')
        .doc(widget.otherUid)
        .get();

    final myData = mySnap.data() ?? {};
    final isMaster = myData['isMaster'] == true;

if (isMaster) {
  _isPremium = true;
}


    final otherData = {
      ...?publicOtherSnap.data(),
      ...?otherSnap.data(),
    };

    String readHomeCode(Map<String, dynamic> data) {
      final home =
          (data['homeCountryCode'] ?? '').toString().trim().toLowerCase();
      if (home.isNotEmpty) return home;

      final code =
          (data['countryCode'] ?? '').toString().trim().toLowerCase();
      if (code.isNotEmpty) return code;

      final country =
          (data['country'] ?? '').toString().trim().toLowerCase();

      if (country == 'canada' || country == 'canadá') return 'ca';
      if (country == 'brazil' || country == 'brasil') return 'br';
      if (country == 'portugal') return 'pt';

      return country;
    }

    _myCountryCode = readHomeCode(myData);
    _otherCountryCode = readHomeCode(otherData);

    _isWorldChat = _myCountryCode.isNotEmpty &&
        _otherCountryCode.isNotEmpty &&
        _myCountryCode != _otherCountryCode;

    debugPrint(
      'CHAT SCOPE => my=$_myCountryCode other=$_otherCountryCode world=$_isWorldChat',
    );

    if (!mounted) return;
    setState(() {});
  } catch (e) {
    debugPrint('Erro _loadChatScope: $e');
  }
}



  void _applyTimerRules() {
  if (!_isWorldChat) {
    _limitReached = false;
    _usageTimer?.cancel();
    _usageTimer = null;
    _remainingVN.value = 0;
    if (mounted) setState(() {});
    return;
  }

  if (_isPremium) {
    _limitReached = false;
    _usageTimer?.cancel();
    _usageTimer = null;
    _remainingVN.value = 0;
    if (mounted) setState(() {});
    return;
  }

  _loadWorldDailyLimitAndStartTimer();
}



 Future<void> _loadWorldDailyLimitAndStartTimer() async {
  try {
    if (!_isWorldChat || _isPremium) return;

    final snap = await myUserDoc.get();
    final data = snap.data() ?? {};

    final used = (data['dailySecondsUsedWorld'] is int)
        ? data['dailySecondsUsedWorld'] as int
        : 0;

    final rawLimit = (data['worldDailyLimitSeconds'] is int)
        ? data['worldDailyLimitSeconds'] as int
        : _freeWorldLimitSeconds;

    final limit = rawLimit < 60 ? _freeWorldLimitSeconds : rawLimit;

    DateTime? lastReset;
    final lr = data['lastDailyResetWorld'];
    if (lr is Timestamp) lastReset = lr.toDate();

    final now = DateTime.now();
    if (lastReset == null || !_isSameDay(lastReset, now)) {
      await myUserDoc.set({
        'dailySecondsUsedWorld': 0,
        'lastDailyResetWorld': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _dailySecondsUsed = 0;
    } else {
      _dailySecondsUsed = used;
    }

    _dailyLimitSeconds = limit;
    _limitReached = (_dailySecondsUsed >= _dailyLimitSeconds);
    _remainingVN.value = _remainingSeconds;

    if (!mounted) return;
    setState(() {});

    _startUsageTimerWorld();
  } catch (e) {
    debugPrint('Erro _loadWorldDailyLimitAndStartTimer: $e');
  }
}



void _startUsageTimerWorld() {
  if (_usageTimer != null) return;

  if (!_isWorldChat || _isPremium || _limitReached) return;

  _usageTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
    if (!mounted) return;

    _dailySecondsUsed += 1;
    _remainingVN.value = _remainingSeconds;

    if (_dailySecondsUsed >= _dailyLimitSeconds) {
      _limitReached = true;
      _usageTimer?.cancel();
      _usageTimer = null;
      setState(() {});
    }

    final now = DateTime.now();
    if (_lastUsageWriteAt == null ||
        now.difference(_lastUsageWriteAt!).inSeconds >= 10) {
      _lastUsageWriteAt = now;
      try {
        await myUserDoc.set({
          'dailySecondsUsedWorld': _dailySecondsUsed,
          'lastSeenAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Erro ao salvar dailySecondsUsedWorld: $e');
      }
    }
  });
}



  Future<void> _markAsRead() async {
    try {
      await convDoc.set({
        'unread': {myUid: 0},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Erro ao marcar como lido: $e');
    }
  }


  Future<void> _setTyping(bool value) async {
    try {
      await _presenceRef.doc(myUid).set({
        'uid': myUid,
        'typing': value,
        'recording': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }


  Future<void> _setRecording(bool value) async {
    try {
      await _presenceRef.doc(myUid).set({
        'uid': myUid,
        'typing': false,
        'recording': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }


  void _onTextChanged() {
    final hasText = _textC.text.trim().isNotEmpty;


    _setTyping(hasText);


    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 1200), () {
      _setTyping(false);
    });


    if (mounted) {
      setState(() {});
    }
  }


  String _presenceLabel(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final t = AppTexts.current;
    final now = DateTime.now();


    bool otherTyping = false;
    bool otherRecording = false;


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


      if (d['recording'] == true) {
        otherRecording = true;
      } else if (d['typing'] == true) {
        otherTyping = true;
      }
    }


    final safeName = widget.otherName.trim().isEmpty
        ? t.get('chat_someone')
        : widget.otherName.trim();


    if (otherRecording) {
      return '$safeName ${t.get('chat_is_recording_audio')}';
    }
    if (otherTyping) {
      return '$safeName ${t.get('chat_is_typing')}';
    }


    return '';
  }


  Future<void> _send() async {
    final t = AppTexts.current;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
if (myUid == null) return;

final mySnap = await FirebaseFirestore.instance
    .collection('users')
    .doc(myUid)
    .get();

if (mySnap.data()?['shadowBan'] == true) {
 
_warn(t.get('user_temporarily_silenced'));

  return;
}


    
 if (_isWorldChat && !_isPremium) {
    
_warn(t.get('chat_user_is_premium'));

    return;
  }


 if (_isWorldChat && _limitReached && !_isPremium) {
  if (!mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const PremiumPage()),
  );
  return;
}


    final blockedNow = await BlockService.isEitherBlocked(widget.otherUid);
    if (blockedNow) return;


    if (_sending) return;


    final now = DateTime.now();
    if (_lastSentAt != null) {
      final diff = now.difference(_lastSentAt!).inMilliseconds;
      if (diff < _cooldownMs) return;
    }


    final text = _textC.text.trim();
    if (text.isEmpty) return;


    if (_containsLink(text)) {
      _warn(t.get('chat_links_not_allowed'));
      return;
    }


    if (_containsPhone(text)) {
      _warn(t.get('chat_phone_not_allowed'));
      return;
    }


    _sending = true;
    _lastSentAt = now;
    _textC.clear();
    _typingDebounce?.cancel();
    await _setTyping(false);


    try {
      final msgData = <String, dynamic>{
        'type': 'text',
        'text': text,
        'senderId': myUid,
        'fromUid': myUid,
        'toUid': widget.otherUid,
        'createdAt': FieldValue.serverTimestamp(),
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
        'replyToMessageId': _replyToMessageId,
        'replyToText': _replyToText,
        'replyToType': _replyToType,
        'replyToIsMe': _replyToIsMe,
        'replyToImageUrl': _replyToImageUrl,
      };


      await msgsCol.add(msgData);
      _cancelReply();


      await db.runTransaction((tx) async {
        final snap = await tx.get(convDoc);
        final data = snap.data() ?? {};


        final unread = Map<String, dynamic>.from(
          (data['unread'] is Map) ? data['unread'] : {},
        );


        final otherCount =
            (unread[widget.otherUid] is int) ? unread[widget.otherUid] as int : 0;


        unread[widget.otherUid] = otherCount + 1;
        unread[myUid] = 0;


        tx.set(convDoc, {
          'participants': [myUid, widget.otherUid],
          'pairKey': '${myUid}_${widget.otherUid}',
          'lastMessage': text,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'unread': unread,
        }, SetOptions(merge: true));
      });


      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_scrollC.hasClients) return;
        _scrollC.jumpTo(0);
      });
    } catch (e) {
      debugPrint('Erro ao enviar: $e');
    } finally {
      _sending = false;
    }
  }


  Future<void> _softDeleteMessage(String messageId) async {
  final t = AppTexts.current;

  try {
    await msgsCol.doc(messageId).update({
      'deleted': true,
      'deletedBy': myUid,
      'deletedText': t.get('chat_message_deleted'),
      'deletedAt': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    debugPrint('Erro ao apagar mensagem: $e');
  }
}




  Future<void> _hideMessageForMe(String messageId) async {
    try {
      await msgsCol.doc(messageId).set({
        'hiddenFor': FieldValue.arrayUnion([myUid]),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Erro ao esconder mensagem para mim: $e');
    }
  }


  void _openMessageActions({
    required String messageId,
  }) {
    final t = AppTexts.current;


    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: Text(t.get('chat_delete_for_me')),
              onTap: () {
                Navigator.pop(context);
                _hideMessageForMe(messageId);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFDC2626),
              ),
              title: Text(
                t.get('chat_delete_for_everyone'),
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _softDeleteMessage(messageId);
              },
            ),
          ],
        ),
      ),
    );
  }


  // =======================
  // ✅ ÁUDIO (UPLOAD + MSG + UNREAD + SCROLL)
  // =======================
  Future<void> _sendAudio(String localPath) async {
    final t = AppTexts.current;
final mySnap = await myUserDoc.get();

if (mySnap.data()?['shadowBan'] == true) {
  await _setRecording(false);
  _warn(t.get('user_temporarily_silenced'));
  return;
}


if (_isWorldChat && _limitReached && !_isPremium) {
  if (!mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const PremiumPage()),
  );
  return;
}



    final blockedNow = await BlockService.isEitherBlocked(widget.otherUid);
    if (blockedNow) return;


    final pendingId = _makePendingId();
    _addPendingAudio(pendingId: pendingId, localPath: localPath);


    try {
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('Arquivo não existe: $localPath');
        return;
      }


      int durationMs = 0;
      final probe = AudioPlayer();
      try {
        await probe.setFilePath(localPath);
        final d = probe.duration;
        durationMs = d?.inMilliseconds ?? 0;
      } catch (e) {
        debugPrint('Não consegui ler duração: $e');
      } finally {
        await probe.dispose();
      }


      final audioUrl = await _uploadAudioToStorage(localPath);


      await msgsCol.add({
        'type': 'audio',
        'audioUrl': audioUrl,
        'durationMs': durationMs,
        'senderId': myUid,
        'fromUid': myUid,
        'toUid': widget.otherUid,
        'createdAt': FieldValue.serverTimestamp(),
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
        'replyToMessageId': _replyToMessageId,
        'replyToText': _replyToText,
        'replyToType': _replyToType,
        'replyToIsMe': _replyToIsMe,
        'replyToImageUrl': _replyToImageUrl,
      });
      _cancelReply();


      await db.runTransaction((tx) async {
        final snap = await tx.get(convDoc);
        final data = snap.data() ?? {};


        final unread = Map<String, dynamic>.from(
          (data['unread'] is Map) ? data['unread'] : {},
        );


        final otherCount =
            (unread[widget.otherUid] is int) ? unread[widget.otherUid] as int : 0;


        unread[widget.otherUid] = otherCount + 1;
        unread[myUid] = 0;


        tx.set(
          convDoc,
          {
            'participants': [myUid, widget.otherUid],
            'pairKey': '${myUid}_${widget.otherUid}',
            'lastMessage': t.get('chat_audio_label'),
            'lastMessageAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'unread': unread,
          },
          SetOptions(merge: true),
        );
      });


      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_scrollC.hasClients) return;
        _scrollC.jumpTo(0);
      });
    } catch (e) {
      debugPrint('Erro ao enviar áudio: $e');
    } finally {
      _removePendingAudio(pendingId);
    }
  }


  Future<String> _uploadAudioToStorage(String localPath) async {
    final fileName = 'remdy_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';


    final ref = FirebaseStorage.instance
        .ref()
        .child('chat_audio/${widget.conversationId}/$fileName');


    final metadata = SettableMetadata(
      contentType: 'audio/mp4',
      customMetadata: {
        'fromUid': myUid,
        'toUid': widget.otherUid,
        'conversationId': widget.conversationId,
      },
    );


    await ref.putFile(File(localPath), metadata);
    return await ref.getDownloadURL();
  }


  Future<String> _uploadImageToStorage(String localPath) async {
    final file = File(localPath);


    if (!await file.exists()) {
      throw Exception('Arquivo da imagem não existe.');
    }


    final fileName = 'remdy_img_${DateTime.now().millisecondsSinceEpoch}.jpg';


    final ref = FirebaseStorage.instance
        .ref()
        .child('chat_images')
        .child(widget.conversationId)
        .child(fileName);


    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {
        'fromUid': myUid,
        'toUid': widget.otherUid,
        'conversationId': widget.conversationId,
      },
    );


    await ref.putFile(file, metadata);
    return await ref.getDownloadURL();
  }


  Future<void> _sendImage(String localPath) async {
    final t = AppTexts.current;
final mySnap = await myUserDoc.get();

if (mySnap.data()?['shadowBan'] == true) {
  _warn(t.get('user_temporarily_silenced'));
  return;
}


 if (_isWorldChat && _limitReached && !_isPremium) {
  if (!mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const PremiumPage()),
  );
  return;
}



    final blockedNow = await BlockService.isEitherBlocked(widget.otherUid);
    if (blockedNow) return;


    final pendingId = _makePendingId();
    _addPendingImage(pendingId: pendingId, localPath: localPath);


    try {
      final file = File(localPath);
      if (!await file.exists()) {
        _warn(t.get('chat_image_not_found'));
        return;
      }


      final size = await file.length();
      if (size <= 0) {
        _warn(t.get('chat_empty_image'));
        return;
      }


      final imageUrl = await _uploadImageToStorage(localPath);


      await msgsCol.add({
        'type': 'image',
        'imageUrl': imageUrl,
        'senderId': myUid,
        'fromUid': myUid,
        'toUid': widget.otherUid,
        'createdAt': FieldValue.serverTimestamp(),
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
        'hiddenFor': <String>[],
        'replyToMessageId': _replyToMessageId,
        'replyToText': _replyToText,
        'replyToType': _replyToType,
        'replyToIsMe': _replyToIsMe,
        'replyToImageUrl': _replyToImageUrl,
      });


      _cancelReply();


      await db.runTransaction((tx) async {
        final snap = await tx.get(convDoc);
        final data = snap.data() ?? {};


        final unread = Map<String, dynamic>.from(
          (data['unread'] is Map) ? data['unread'] : {},
        );


        final otherCount =
            (unread[widget.otherUid] is int) ? unread[widget.otherUid] as int : 0;


        unread[widget.otherUid] = otherCount + 1;
        unread[myUid] = 0;


        tx.set(
          convDoc,
          {
            'participants': [myUid, widget.otherUid],
            'pairKey': '${myUid}_${widget.otherUid}',
            'lastMessage': t.get('chat_photo_label'),
            'lastMessageAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'unread': unread,
          },
          SetOptions(merge: true),
        );
      });


      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_scrollC.hasClients) return;
        _scrollC.jumpTo(0);
      });
    } catch (e) {
      _warn('${t.get('chat_error_sending_image')} $e');
      debugPrint('Erro ao enviar imagem: $e');
    } finally {
      _removePendingImage(pendingId);
    }
  }


  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );


      if (file == null) return;


      await _sendImage(file.path);
    } catch (e) {
      debugPrint('Erro ao selecionar imagem: $e');
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
              title: Text(t.get('chat_gallery')),
              onTap: () async {
                Navigator.pop(context);
                await _pickAndSendImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(t.get('chat_camera')),
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


  @override
  void initState() {
    super.initState();


    _textC.addListener(_onTextChanged);


    _disableForegroundPushUI();


    _msgsStream = msgsCol.orderBy('createdAt', descending: true).snapshots();
    _otherUserStream = otherUserDoc.snapshots();
    _blockedStream = BlockService.isEitherBlockedStream(widget.otherUid);


    _msgsSub = _msgsStream.listen((_) {
      _markAsRead();
    });


    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markAsRead();
    });


    _loadChatScope().then((_) {
      _listenPremium();
      _applyTimerRules();
    });
  }


  @override
  void dispose() {
    _msgsSub?.cancel();
    _msgsSub = null;


    _markAsRead();


    _typingDebounce?.cancel();
    _setTyping(false);
    _setRecording(false);


    _premiumSub?.cancel();
    _premiumSub = null;


    _usageTimer?.cancel();
    _usageTimer = null;


    _textC.removeListener(_onTextChanged);
    _remainingVN.dispose();
    _textC.dispose();
    _scrollC.dispose();
    super.dispose();
  }


  void _openPublicProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PublicProfilePage(userUid: widget.otherUid)),
    );
  }


Future<void> _openReplySearch() async {
  final result = await Navigator.push<_ReplySearchResult>(
    context,
    MaterialPageRoute(
      builder: (_) => _ReplySearchPage(
        conversationId: widget.conversationId,
        myUid: myUid,
        otherName: widget.otherName,
      ),
    ),
  );

  if (!mounted || result == null) return;

  _handleReplyFromMessage(result.message, result.type);
}



  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
String _formatDayLabel(Timestamp? ts) {
  final t = AppTexts.current;

  if (ts == null) return t.get('chat_today');

  final d = ts.toDate();
  final now = DateTime.now();

  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);

  final diff = today.difference(day).inDays;

  if (diff == 0) return t.get('chat_today');
  if (diff == 1) return t.get('chat_yesterday');

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


Future<void> _sendChatReport(BuildContext context, String reason) async {
  final t = AppTexts.current;
  try {
    await FirebaseFirestore.instance.collection('reports').add({
      'fromUid': myUid,
      'reportedUid': widget.otherUid,
      'reason': reason,
      'status': 'open',
      'contextType': 'dm',
      'conversationId': widget.conversationId,
      'source': 'chat_page',
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(t.get('report_sent'))),

    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      
SnackBar(content: Text('${t.get('error_prefix')} $e')),

    );
  }
}

void _openChatReportSheet() {
  final t = AppTexts.current;
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.report),
           title: Text('${t.get('report_user')} ${widget.otherName}'),
          ),
          ListTile(
            title: Text(t.get('report_reason_inappropriate')),
            onTap: () {
              Navigator.pop(context);
              _sendChatReport(context, 'Conteúdo impróprio');
            },
          ),
          ListTile(
            title: Text(t.get('report_reason_spam')),
            onTap: () {
              Navigator.pop(context);
             _sendChatReport(context, t.get('report_reason_spam'));
            },
          ),
          ListTile(
            title:Text(t.get('report_reason_harassment')),
            onTap: () {
              Navigator.pop(context);
             _sendChatReport(context, t.get('report_reason_harassment'));
            },
          ),
          ListTile(
            title:Text(t.get('report_reason_threat')),
            onTap: () {
              Navigator.pop(context);
          _sendChatReport(context, t.get('report_reason_threat'));
            },
          ),
        ListTile(
  title: Text(t.get('report_reason_other')),
  onTap: () {
    Navigator.pop(context);
    _sendChatReport(
      context,
      t.get('report_reason_other'),
    );
  },
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
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        iconTheme: const IconThemeData(color: _text),
      title: _searchMode
    ? TextField(
        controller: _searchController,
        autofocus: true,
        decoration:  InputDecoration(
          hintText: t.get('chat_search_message_hint'),
          border: InputBorder.none,
        ),
        onChanged: (value) {
          setState(() {
            _searchText = value.trim().toLowerCase();
          });
        },
        style: TextStyle( // ⚠️ tira o const aqui
          color: _text,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      )

    : Row(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _otherUserStream,
            builder: (context, snap) {
              final data = snap.data?.data() ?? {};
              final photoUrl =
                  (data['photoUrl'] ?? data['photoURL'] ?? data['photo'] ?? '')
                      .toString()
                      .trim();

              final avatar = CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFF1F5F9),
                backgroundImage:
                    photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl.isEmpty
                    ? Text(
                        widget.otherName.isNotEmpty
                            ? widget.otherName.substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _text,
                        ),
                      )
                    : null,
              );

              return InkWell(
                onTap: _openPublicProfile,
                borderRadius: BorderRadius.circular(999),
                child: AvatarWithOnlineDot(
                  uid: widget.otherUid,
                  dotSize: 10,
                  avatar: avatar,
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: _openPublicProfile,
              child: Text(
                widget.otherName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15.5,
                  color: _text,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_isPremium)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7CC),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFFFE08A)),
              ),
              child: Text(
                t.get('chat_premium'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: _text,
                ),
              ),
            ),
        ],
      ),





actions: [
  if (!_searchMode)
    IconButton(
      onPressed: _openChatReportSheet,
      icon: const Icon(
        Icons.flag_outlined,
        color: _text,
      ),
      tooltip: 'Reportar',
    ),
  _searchMode
      ? IconButton(
          onPressed: () {
            setState(() {
              _searchMode = false;
              _searchText = '';
              _searchController.clear();
            });
          },
          icon: const Icon(
            Icons.close,
            color: _text,
          ),
        )
      : IconButton(
          onPressed: () {
            setState(() {
              _searchMode = true;
            });
          },
          icon: const Icon(
            Icons.search_rounded,
            color: _text,
          ),
        ),
],




      ),
      body: Column(
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
            child: StreamBuilder<bool>(
              stream: _blockedStream,
              initialData: false,
              builder: (context, blockSnap) {
               final isBlocked = blockSnap.data ?? false;

final lockByCountry = _isWorldChat && !_isPremium;
final locked = isBlocked || (_isWorldChat && !_isPremium);



                return Column(
                  children: [
                    Expanded(
                      child: isBlocked
                          ? Center(
                              child: Text(
                                t.get('chat_unavailable_blocked'),
                              ),
                            )
                          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: _msgsStream,
                              builder: (context, snap) {
                                if (!snap.hasData) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                if (snap.hasError) {
                                  return Center(
                                    child: Text(
                                      '${t.get('chat_error_prefix')} ${snap.error}',
                                    ),
                                  );
                                }


final docs = snap.data?.docs ?? [];
final pendingItems = _buildPendingItems();
final totalCount = pendingItems.length + docs.length;







if (totalCount == 0) {
  return Center(
    child: Text(
      t.get('chat_no_messages_yet'),
    ),
  );
}




                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (!_scrollC.hasClients) return;
                                  if (totalCount != _lastMsgCount) {
                                    _lastMsgCount = totalCount;
                                    _scrollC.jumpTo(0);
                                  }
                                });


                                return ListView.builder(
                                  controller: _scrollC,
                                  reverse: true,
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 12, 12, 12),
                                  itemCount: totalCount,
                                  itemBuilder: (context, i) {
                                    if (i < pendingItems.length) {
                                      final pending = pendingItems[i];


                                      if (pending.type == 'audio') {
                                        return const _AudioSendingBubble(
                                          isMe: true,
                                        );
                                      }


                                      return const _ImageSendingBubble(
                                        isMe: true,
                                      );
                                    }


final docIndex = i - pendingItems.length;

if (docIndex < 0 || docIndex >= docs.length) {
  return const SizedBox.shrink();
}

final d = docs[docIndex].data();

final textSearch = (d['text'] ?? '').toString().toLowerCase();

if (_searchMode && _searchText.isNotEmpty) {
  if (!textSearch.contains(_searchText)) {
    return const SizedBox(height: 0);
  }
}





                                    final msg = {
                                      ...d,
                                      'id': docs[docIndex].id,
                                    };


                                    final hiddenRaw = d['hiddenFor'];
                                    final hiddenFor = (hiddenRaw is List)
                                        ? hiddenRaw
                                            .map((e) => e.toString())
                                            .toList()
                                        : <String>[];


                                    if (hiddenFor.contains(myUid)) {
                                      return const SizedBox.shrink();
                                    }


                                    final senderId =
                                        (d['senderId'] ?? '').toString();
                                    final isMe = senderId == myUid;


                                    final replyToImageUrl =
                                        (d['replyToImageUrl'] ?? '').toString();


                                    final type =
                                        (d['type'] ?? 'text').toString();
                                    final deleted = d['deleted'] == true;
                                    final createdAt =
                                        d['createdAt'] as Timestamp?;
                                    final timeText = _formatTime(createdAt);


                                    if (type == 'audio') {
                                      if (deleted) {
                                        return _Bubble(
                                          text: t.get('chat_audio_deleted'),
                                          isMe: isMe,
                                          isDeleted: true,
                                          timeText: timeText,
                                          replyToText: '',
                                          replyToType: 'text',
                                          replyToIsMe: false,
                                          replyToImageUrl: replyToImageUrl,
                                        );
                                      }


                                      final url =
                                          (d['audioUrl'] ?? '').toString();


                                      final rawDuration = d['durationMs'] ?? 0;
                                      final durationMs = rawDuration is int
                                          ? rawDuration
                                          : (rawDuration is num
                                              ? rawDuration.toInt()
                                              : 0);


                                      return GestureDetector(
                                        onHorizontalDragUpdate: (details) {
                                          _dragDx += details.delta.dx;
                                        },
                                        onHorizontalDragEnd: (_) {
                                          if (_dragDx > 35) {
                                            _handleReplyFromMessage(
                                                msg, 'audio');
                                          }
                                          _dragDx = 0;
                                        },
                                        onHorizontalDragCancel: () {
                                          _dragDx = 0;
                                        },
                                        onLongPress: () {
                                          if (!isMe) return;
                                          _openMessageActions(
                                              messageId: docs[docIndex].id);
                                        },
                                        child: AudioBubble(
                                          messageId: docs[docIndex].id,
                                          audioUrl: url,
                                          isMe: isMe,
                                          durationMs: durationMs,
                                          timeText: timeText,
                                        ),
                                      );
                                    }


                                    if (type == 'image') {
                                      if (deleted) {
                                        return _Bubble(
                                          text: t.get('chat_photo_deleted'),
                                          isMe: isMe,
                                          isDeleted: true,
                                          timeText: timeText,
                                          replyToText: '',
                                          replyToType: 'text',
                                          replyToIsMe: false,
                                          replyToImageUrl: replyToImageUrl,
                                        );
                                      }


                                      final imageUrl =
                                          (d['imageUrl'] ?? '').toString();


                                      return GestureDetector(
                                        onHorizontalDragUpdate: (details) {
                                          _dragDx += details.delta.dx;
                                        },
                                        onHorizontalDragEnd: (_) {
                                          if (_dragDx > 35) {
                                            _handleReplyFromMessage(
                                                msg, 'image');
                                          }
                                          _dragDx = 0;
                                        },
                                        onHorizontalDragCancel: () {
                                          _dragDx = 0;
                                        },
                                        onLongPress: () {
                                          if (!isMe) return;
                                          _openMessageActions(
                                              messageId: docs[docIndex].id);
                                        },
                                        child: _ImageBubble(
                                          imageUrl: imageUrl,
                                          isMe: isMe,
                                          timeText: timeText,
                                        ),
                                      );
                                    }


                                    final text = (d['text'] ?? '').toString();
                                    final replyToText =
                                        (d['replyToText'] ?? '').toString();
                                    final replyToType =
                                        (d['replyToType'] ?? 'text').toString();
                                    final replyToIsMe =
                                        d['replyToIsMe'] == true;


                                    if (deleted) {
                                      return _Bubble(
                                        text: t.get('chat_message_deleted'),
                                        isMe: isMe,
                                        isDeleted: true,
                                        timeText: timeText,
                                        replyToText: '',
                                        replyToType: 'text',
                                        replyToIsMe: false,
                                        replyToImageUrl: '',
                                      );
                                    }



final showDate = _shouldShowDateHeader(docs, docIndex);

return Column(
  children: [
    if (showDate)
      _DateHeader(label: _formatDayLabel(createdAt)),

    GestureDetector(
      behavior: HitTestBehavior.opaque,

  onTap: () {
    if (!_searchMode) return;

    _handleReplyFromMessage(msg, 'text');

    setState(() {
      _searchMode = false;
      _searchText = '';
      _searchController.clear();
    });
  },
  onHorizontalDragUpdate: (details) {
    _dragDx += details.delta.dx;
  },
  onHorizontalDragEnd: (_) {
    if (_dragDx > 35) {
      _handleReplyFromMessage(msg, 'text');
    }
    _dragDx = 0;
  },
  onHorizontalDragCancel: () {
    _dragDx = 0;
  },
  onLongPress: () {
    if (!isMe) return;
    _openMessageActions(
      messageId: docs[docIndex].id,
    );
  },
  child: _Bubble(
    text: text,
    isMe: isMe,
    isDeleted: false,
    timeText: timeText,
    replyToText: replyToText,
    replyToType: replyToType,
    replyToIsMe: replyToIsMe,
    replyToImageUrl: replyToImageUrl,
  ),
  
),
],
);

                                  },
                                );
                              },
                            ),
                    ),


                   
if (_isWorldChat && !_isPremium && _limitReached)

                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: ValueListenableBuilder<int>(
                          valueListenable: _remainingVN,
                          builder: (_, remaining, __) {
                            return Text(
                              _limitReached
                                  ? t.get('chat_world_time_ended_today')
                                  : '${t.get('chat_world_time_today')} ${_formatSeconds(remaining)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _muted,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            );
                          },
                        ),
                      ),
                    SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: _card,
                          border: Border(top: BorderSide(color: _border)),
                        ),
                        child: Column(
                          children: [
                            if (_replyToMessageId != null)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border(
                                    left: BorderSide(
                                      color:
                                          _replyToIsMe ? _remdyBlue : _muted,
                                      width: 4,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _replyToIsMe
                                                ? t.get('chat_you')
                                                : t.get('chat_reply'),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: _text,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          if (_replyToType == 'image' && _replyToImageUrl.isNotEmpty)
  Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          _replyToImageUrl,
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 42,
            height: 42,
            color: const Color(0xFFE5E7EB),
            alignment: Alignment.center,
            child: const Icon(Icons.image, size: 18),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          t.get('chat_photo_label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            color: _muted,
          ),
        ),
      ),
    ],
  )
else
  Text(
    _replyToType == 'audio'
        ? t.get('chat_audio_label')
        : _replyToType == 'image'
            ? t.get('chat_photo_label')
            : _replyToText,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      fontSize: 13,
      color: _muted,
    ),
  ),

                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: _cancelReply,
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                                  ],
                                ),
                              ),
                            Row(
                              children: [
                                Expanded(
                              child: Container(
  decoration: BoxDecoration(
    color: const Color(0xFFF1F5F9),
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: _border),
  ),
  padding: const EdgeInsets.symmetric(horizontal: 14),
  child: TextField(
    controller: _textC,
   enabled: !(_isWorldChat && !_isPremium),
    textInputAction: TextInputAction.send,
    onSubmitted: (_) async {
      if (locked) return;
      await _setTyping(false);
      await _send();
    },
    decoration: InputDecoration(
hintText: (_isWorldChat && !_isPremium)
    ? t.get('chat_user_is_premium')
    : isBlocked
        ? t.get('chat_cannot_send_blocked')
        : t.get('chat_type_message'),





      border: InputBorder.none,
    ),
  ),
),

                                ),
                                const SizedBox(width: 8),
                                Opacity(
                                  opacity: locked ? 0.45 : 1.0,
                                  child: InkWell(
                                    onTap: (_isWorldChat && !_isPremium) ? null : _openPlusMenu,
                                    borderRadius: BorderRadius.circular(999),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        border: Border.all(color: _border),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x08000000),
                                            blurRadius: 8,
                                            offset: Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.add_rounded,
                                        color: _remdyBlue,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _textC.text.trim().isEmpty
                                    ? Opacity(
                                        opacity: locked ? 0.45 : 1.0,
                                        child: IgnorePointer(
                                        ignoring: (_isWorldChat && !_isPremium),
                                          child: RecordingButton(
                                            onRecordStart: () async {
                                              await _setRecording(true);
                                            },
                                            onRecordStop: () async {
                                              await _setRecording(false);
                                            },
                                         
onRecorded: (path) async {
  await _setRecording(false);

  if (path == null) return;

  await _sendAudio(path);
},


                                          ),
                                        ),
                                      )
                                    : Opacity(
                                        opacity: (_isWorldChat && !_isPremium) ? 0.45 : 1.0,
                                        child: InkWell(
                                          onTap: (_isWorldChat && !_isPremium) ? null : _send,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          child: Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  _remdyBlue,
                                                  _logoBlue
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Color(0x14000000),
                                                  blurRadius: 10,
                                                  offset: Offset(0, 5),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.send_rounded,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
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


class _PendingAudioItem {
  final String pendingId;
  final String localPath;
  final DateTime createdAt;


  const _PendingAudioItem({
    required this.pendingId,
    required this.localPath,
    required this.createdAt,
  });
}


class _PendingImageItem {
  final String pendingId;
  final String localPath;
  final DateTime createdAt;


  const _PendingImageItem({
    required this.pendingId,
    required this.localPath,
    required this.createdAt,
  });
}


class _PendingChatListItem {
  final String pendingId;
  final String type;
  final DateTime createdAt;


  const _PendingChatListItem._({
    required this.pendingId,
    required this.type,
    required this.createdAt,
  });


  factory _PendingChatListItem.audio({
    required String pendingId,
    required DateTime createdAt,
  }) {
    return _PendingChatListItem._(
      pendingId: pendingId,
      type: 'audio',
      createdAt: createdAt,
    );
  }


  factory _PendingChatListItem.image({
    required String pendingId,
    required DateTime createdAt,
  }) {
    return _PendingChatListItem._(
      pendingId: pendingId,
      type: 'image',
      createdAt: createdAt,
    );
  }
}


class _AudioSendingBubble extends StatelessWidget {
  final bool isMe;


  const _AudioSendingBubble({
    required this.isMe,
  });


  static const Color _text = Color(0xFF111827);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final bg = isMe ? _remdyBlue : Colors.white;
    final fg = isMe ? Colors.white : _text;


    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: isMe ? null : Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isMe ? Colors.white : _remdyBlue,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                t.get('chat_sending_audio'),
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
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


  const _ImageSendingBubble({
    required this.isMe,
  });


  static const Color _remdyBlue = Color(0xFF313A5F);


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;


    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
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
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withOpacity(0.10)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.image_outlined,
                size: 42,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isMe ? Colors.white : _remdyBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    t.get('chat_sending_image'),
                    style: TextStyle(
                      color: isMe ? Colors.white : const Color(0xFF111827),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
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
              if (timeText.isNotEmpty) ...[
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


  final String replyToText;
  final String replyToType;
  final bool replyToIsMe;
  final String replyToImageUrl;


  const _Bubble({
    super.key,
    required this.text,
    required this.isMe,
    required this.isDeleted,
    required this.timeText,
    required this.replyToText,
    required this.replyToType,
    required this.replyToIsMe,
    required this.replyToImageUrl,
  });


  static const Color _text = Color(0xFF111827);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final bg = isMe ? _remdyBlue : Colors.white;
    final fg = isMe ? Colors.white : _text;


    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: isMe ? null : Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (replyToText.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isMe
                      ? Colors.white.withOpacity(0.14)
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(
                      color: isMe ? Colors.white70 : _remdyBlue,
                      width: 4,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      replyToIsMe ? t.get('chat_you') : t.get('chat_reply'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isMe ? Colors.white70 : _text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (replyToType == 'image' && replyToImageUrl.isNotEmpty)
                      Row(
                        children: [
                          if (replyToType == 'image' &&
                              replyToImageUrl.isNotEmpty) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                replyToImageUrl,
                                width: 42,
                                height: 42,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 42,
                                  height: 42,
                                  color: const Color(0xFFE5E7EB),
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.image, size: 18),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              replyToType == 'audio'
                                  ? t.get('chat_audio_label')
                                  : replyToType == 'image'
                                      ? t.get('chat_photo_label')
                                      : replyToText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: isMe
                                    ? Colors.white70
                                    : const Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                  if (replyToType == 'image' && replyToImageUrl.isNotEmpty)
  Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          replyToImageUrl,
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 42,
            height: 42,
            color: const Color(0xFFE5E7EB),
            alignment: Alignment.center,
            child: const Icon(Icons.image, size: 18),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          t.get('chat_photo_label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: isMe ? Colors.white70 : const Color(0xFF6B7280),
          ),
        ),
      ),
    ],
  )
else
  Text(
    replyToType == 'audio'
        ? t.get('chat_audio_label')
        : replyToType == 'image'
            ? t.get('chat_photo_label')
            : replyToText,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 13,
      color: isMe ? Colors.white70 : const Color(0xFF6B7280),
    ),
  ),

                  ],
                ),
              ),
            Text(
              text,
              style: TextStyle(
                color: isDeleted
                    ? (isMe ? Colors.white70 : const Color(0xFF6B7280))
                    : fg,
                fontWeight: FontWeight.w600,
                fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                fontSize: isDeleted ? 12.5 : 14,
                height: 1.25,
              ),
            ),
            if (timeText.isNotEmpty) ...[
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
          ],
        ),
      ),
    );
  }
}

class _ReplySearchPage extends StatefulWidget {
  final String conversationId;
  final String myUid;
  final String otherName;

  const _ReplySearchPage({
    required this.conversationId,
    required this.myUid,
    required this.otherName,
  });

  @override
  State<_ReplySearchPage> createState() => _ReplySearchPageState();
}

class _ReplySearchPageState extends State<_ReplySearchPage> {
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  final _searchC = TextEditingController();
  String _query = '';

  String _messagePreviewText(Map<String, dynamic> d, String fallbackType) {
    final type = (d['type'] ?? fallbackType).toString();

    if (d['deleted'] == true) return 'Mensagem apagada';
    if (type == 'audio') return 'Áudio';
    if (type == 'image') return 'Foto';

    final text = (d['text'] ?? '').toString().trim();
    if (text.isNotEmpty) return text;

    return 'Mensagem';
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgsFuture = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .get();

    return Scaffold(
      appBar: AppBar(
        title: Text(
  AppTexts.current.get('chat_search_message'),

          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
          ),
        ),
        iconTheme: const IconThemeData(color: _text),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _searchC,
                autofocus: true,
                decoration:  InputDecoration(
                hintText: AppTexts.current.get('chat_search_hint'),

                  border: InputBorder.none,
                ),
                onChanged: (v) {
                  setState(() {
                    _query = v.trim().toLowerCase();
                  });
                },
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: msgsFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snap.hasError) {
                  return  Center(
              child: Text(
  AppTexts.current.get('chat_error_loading_messages'),
  style: const TextStyle(color: _muted),
),

                  );
                }

                final docs = snap.data?.docs ?? [];

                final results = docs.where((doc) {
                  final d = doc.data();

                  final hiddenRaw = d['hiddenFor'];
                  final hiddenFor = (hiddenRaw is List)
                      ? hiddenRaw.map((e) => e.toString()).toList()
                      : <String>[];

                  if (hiddenFor.contains(widget.myUid)) return false;
                  if (d['deleted'] == true) return false;
                  if (_query.isEmpty) return false;

                  final preview = _messagePreviewText(
                    d,
                    (d['type'] ?? 'text').toString(),
                  ).toLowerCase();

                  return preview.contains(_query);
                }).toList();

                if (_query.isEmpty) {
                  return  Center(
                    child: Text(
                      AppTexts.current.get('chat_search_empty'),
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }

                if (results.isEmpty) {
                  return  Center(
                    child: Text(
                      AppTexts.current.get('chat_search_no_results'),
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final doc = results[i];
                    final d = doc.data();
                    final type = (d['type'] ?? 'text').toString();
                    final preview = _messagePreviewText(d, type);
                    final isMe =
                        (d['senderId'] ?? '').toString() == widget.myUid;
                    final timeText = _formatTime(d['createdAt'] as Timestamp?);

                    return ListTile(
                      leading: Icon(
                        type == 'audio'
                            ? Icons.mic_rounded
                            : type == 'image'
                                ? Icons.image_rounded
                                : Icons.chat_bubble_outline_rounded,
                        color: _muted,
                      ),
                      title: Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${isMe ? "Você" : widget.otherName}${timeText.isNotEmpty ? " • $timeText" : ""}',
                      ),
                      onTap: () {
                        Navigator.pop(
                          context,
                          _ReplySearchResult(
                            message: {
                              ...d,
                              'id': doc.id,
                            },
                            type: type,
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplySearchResult {
  final Map<String, dynamic> message;
  final String type;

  const _ReplySearchResult({
    required this.message,
    required this.type,
  });
}
