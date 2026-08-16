import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
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
import '../pages/forward_message_page.dart';
import '../services/forward_message_service.dart';
import '../services/dm_reply_quota.dart';
import '../services/international_chat_service.dart';
import '../services/premium_access_service.dart';
import '../services/send_dm_message_service.dart';
import '../services/report_category.dart';
import '../services/voice_service.dart';
import '../services/app_notification_state.dart';
import '../utils/chat_message_list_stability.dart';
import '../widgets/international_premium_dialog.dart';
import '../widgets/message_text_with_links.dart';
import '../widgets/link_preview_card.dart';
import '../services/link_preview_service.dart';
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
  final List<_PendingTextItem> _pendingTexts = [];

  /// Último snapshot válido — evita spinner que apaga a lista.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _cachedMsgDocs = const [];
  final Set<String> _inFlightPendingIds = {};

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

  /// Último replyQuota confirmado pela Callable (otimista até o snapshot do conv).
  DmReplyQuota? _quotaFromCallable;
  int _draftCodePoints = 0;

  bool get _usesReplyQuota => DmSendPath.requiresCallable(
        senderIsPremium: _isPremium,
        isInternational: _isWorldChat,
      );

  DmReplyQuota _effectiveReplyQuotaFrom(Map<String, dynamic>? convData) {
    if (!_usesReplyQuota) {
      return const DmReplyQuota(
        used: 0,
        limit: DmReplyQuota.defaultLimit,
        freeUid: '',
        enabled: false,
      );
    }
    final parsed = DmReplyQuota.fromMap(
      convData?['replyQuota'] is Map
          ? Map<String, dynamic>.from(convData!['replyQuota'] as Map)
          : null,
      expectFreeUid: myUid,
    );
    if (_quotaFromCallable != null && _quotaFromCallable!.used >= parsed.used) {
      return _quotaFromCallable!;
    }
    if (parsed.enabled && (parsed.freeUid.isEmpty || parsed.freeUid == myUid)) {
      return parsed.enabled
          ? parsed
          : DmReplyQuota(
              used: parsed.used,
              limit: DmReplyQuota.defaultLimit,
              freeUid: myUid,
              enabled: true,
            );
    }
    return DmReplyQuota(
      used: 0,
      limit: DmReplyQuota.defaultLimit,
      freeUid: myUid,
      enabled: true,
    );
  }

  /// Compat: getters usados em _ensureCanSendMessage antes do StreamBuilder.
  DmReplyQuota get _effectiveReplyQuota =>
      _quotaFromCallable ??
      DmReplyQuota(
        used: 0,
        limit: DmReplyQuota.defaultLimit,
        freeUid: myUid,
        enabled: _usesReplyQuota,
      );

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

  bool _containsPhone(String text) {
    final t = text.trim();
    final intl = RegExp(r'\+\s?\d{1,3}');
    final generic = RegExp(r'\d[\d\s().-]{7,}\d');
    return intl.hasMatch(t) || generic.hasMatch(t);
  }

  String _makePendingId() {
    // ID real do Firestore gerado antecipadamente (mesmo ID no local e no servidor).
    return msgsCol.doc().id;
  }

  _PendingReplyData _captureReplyData() {
    return _PendingReplyData(
      replyToMessageId: _replyToMessageId,
      replyToText: _replyToText,
      replyToType: _replyToType,
      replyToIsMe: _replyToIsMe,
      replyToImageUrl: _replyToImageUrl,
    );
  }

  void _syncPendingWithServerIds(Set<String> serverIds) {
    final nextAudios =
        ChatMessageListStability.pruneConfirmedPending<_PendingAudioItem>(
      pending: _pendingAudios,
      idOf: (_PendingAudioItem e) => e.pendingId,
      serverIds: serverIds,
    );
    final nextImages =
        ChatMessageListStability.pruneConfirmedPending<_PendingImageItem>(
      pending: _pendingImages,
      idOf: (_PendingImageItem e) => e.pendingId,
      serverIds: serverIds,
    );
    final nextTexts =
        ChatMessageListStability.pruneConfirmedPending<_PendingTextItem>(
      pending: _pendingTexts,
      idOf: (_PendingTextItem e) => e.pendingId,
      serverIds: serverIds,
    );
    if (nextAudios.length == _pendingAudios.length &&
        nextImages.length == _pendingImages.length &&
        nextTexts.length == _pendingTexts.length) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      setState(() {
        _pendingAudios
          ..clear()
          ..addAll(nextAudios);
        _pendingImages
          ..clear()
          ..addAll(nextImages);
        _pendingTexts
          ..clear()
          ..addAll(nextTexts);
        for (final id in serverIds) {
          _inFlightPendingIds.remove(id);
        }
      });
    });
  }

  bool _beginPendingSend(String pendingId) {
    if (ChatMessageListStability.shouldIgnoreConcurrentSend(
      sending: _inFlightPendingIds.contains(pendingId),
    )) {
      return false;
    }
    _inFlightPendingIds.add(pendingId);
    return true;
  }

  void _endPendingSend(String pendingId) {
    _inFlightPendingIds.remove(pendingId);
  }

  void _patchPendingAudio(
    String pendingId, {
    bool? failed,
    bool? sending,
    String? uploadedUrl,
    int? durationMs,
  }) {
    if (!mounted) return;
    setState(() {
      final i = _pendingAudios.indexWhere((e) => e.pendingId == pendingId);
      if (i < 0) return;
      _pendingAudios[i] = _pendingAudios[i].copyWith(
        failed: failed,
        sending: sending,
        uploadedUrl: uploadedUrl,
        durationMs: durationMs,
      );
    });
  }

  void _patchPendingImage(
    String pendingId, {
    bool? failed,
    bool? sending,
    String? uploadedUrl,
  }) {
    if (!mounted) return;
    setState(() {
      final i = _pendingImages.indexWhere((e) => e.pendingId == pendingId);
      if (i < 0) return;
      _pendingImages[i] = _pendingImages[i].copyWith(
        failed: failed,
        sending: sending,
        uploadedUrl: uploadedUrl,
      );
    });
  }

  void _patchPendingText(
    String pendingId, {
    bool? failed,
    bool? sending,
  }) {
    if (!mounted) return;
    setState(() {
      final i = _pendingTexts.indexWhere((e) => e.pendingId == pendingId);
      if (i < 0) return;
      _pendingTexts[i] = _pendingTexts[i].copyWith(
        failed: failed,
        sending: sending,
      );
    });
  }

  void _markPendingAudioFailed(String pendingId) {
    _endPendingSend(pendingId);
    _patchPendingAudio(pendingId, failed: true, sending: false);
  }

  void _markPendingImageFailed(String pendingId) {
    _endPendingSend(pendingId);
    _patchPendingImage(pendingId, failed: true, sending: false);
  }

  void _markPendingTextFailed(String pendingId) {
    _endPendingSend(pendingId);
    _patchPendingText(pendingId, failed: true, sending: false);
  }

  void _addPendingAudio({
    required String pendingId,
    required String localPath,
    required _PendingReplyData reply,
  }) {
    if (!mounted) return;
    setState(() {
      _pendingAudios.insert(
        0,
        _PendingAudioItem(
          pendingId: pendingId,
          localPath: localPath,
          createdAt: DateTime.now(),
          reply: reply,
          sending: true,
        ),
      );
    });
  }

  void _addPendingImage({
    required String pendingId,
    required String localPath,
    required _PendingReplyData reply,
  }) {
    if (!mounted) return;
    setState(() {
      _pendingImages.insert(
        0,
        _PendingImageItem(
          pendingId: pendingId,
          localPath: localPath,
          createdAt: DateTime.now(),
          reply: reply,
          sending: true,
        ),
      );
    });
  }

  void _addPendingText({
    required String pendingId,
    required String text,
    required _PendingReplyData reply,
  }) {
    if (!mounted) return;
    setState(() {
      _pendingTexts.insert(
        0,
        _PendingTextItem(
          pendingId: pendingId,
          text: text,
          createdAt: DateTime.now(),
          reply: reply,
          sending: true,
        ),
      );
    });
  }

  List<_PendingChatListItem> _buildPendingItems(Set<String> serverIds) {
    final items = <_PendingChatListItem>[
      ..._pendingAudios
          .where(
            (e) => ChatMessageListStability.shouldShowPending(
              pendingId: e.pendingId,
              serverIds: serverIds,
            ),
          )
          .map(
            (e) => _PendingChatListItem.audio(
              pendingId: e.pendingId,
              createdAt: e.createdAt,
              localPath: e.localPath,
              failed: e.failed,
              sending: e.sending,
            ),
          ),
      ..._pendingImages
          .where(
            (e) => ChatMessageListStability.shouldShowPending(
              pendingId: e.pendingId,
              serverIds: serverIds,
            ),
          )
          .map(
            (e) => _PendingChatListItem.image(
              pendingId: e.pendingId,
              createdAt: e.createdAt,
              localPath: e.localPath,
              failed: e.failed,
              sending: e.sending,
            ),
          ),
      ..._pendingTexts
          .where(
            (e) => ChatMessageListStability.shouldShowPending(
              pendingId: e.pendingId,
              serverIds: serverIds,
            ),
          )
          .map(
            (e) => _PendingChatListItem.text(
              pendingId: e.pendingId,
              createdAt: e.createdAt,
              text: e.text,
              failed: e.failed,
              sending: e.sending,
            ),
          ),
    ];

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  void _notifySendFailed() {
    if (!mounted) return;
    _warn(AppTexts.current.get('chat_send_failed'));
  }

  Future<void> _retryPendingAudio(String pendingId) async {
    final i = _pendingAudios.indexWhere((e) => e.pendingId == pendingId);
    if (i < 0) return;
    final item = _pendingAudios[i];
    if (!ChatMessageListStability.canStartRetry(
      failed: item.failed,
      sending: item.sending || _inFlightPendingIds.contains(pendingId),
    )) {
      return;
    }
    await _sendAudio(item.localPath, retryMessageId: pendingId);
  }

  Future<void> _retryPendingImage(String pendingId) async {
    final i = _pendingImages.indexWhere((e) => e.pendingId == pendingId);
    if (i < 0) return;
    final item = _pendingImages[i];
    if (!ChatMessageListStability.canStartRetry(
      failed: item.failed,
      sending: item.sending || _inFlightPendingIds.contains(pendingId),
    )) {
      return;
    }
    await _sendImage(item.localPath, retryMessageId: pendingId);
  }

  Future<void> _retryPendingText(String pendingId) async {
    final i = _pendingTexts.indexWhere((e) => e.pendingId == pendingId);
    if (i < 0) return;
    final item = _pendingTexts[i];
    if (!ChatMessageListStability.canStartRetry(
      failed: item.failed,
      sending: item.sending || _inFlightPendingIds.contains(pendingId),
    )) {
      return;
    }
    await _send(retryMessageId: pendingId);
  }

  void _listenPremium() {
    _premiumSub?.cancel();

    _premiumSub = myUserDoc.snapshots().listen((snap) {
      final data = snap.data() ?? {};

      final paid = data['isPremium'] == true;
      final master = data['isMaster'] == true;
      final until =
          PremiumAccessService.parsePremiumUntil(data['premiumUntil']);
      final timePremiumActive = PremiumAccessService.hasActiveTimePremium(data);

      _isPremiumPaid = paid;
      _hasActiveTimePremium = timePremiumActive;
      _premiumUntil = until;

      final active = PremiumAccessService.isPremiumActiveFromData(data);

      if (!context.mounted) return;
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

      final publicOtherSnap =
          await db.collection('publicUsers').doc(widget.otherUid).get();

      final myData = mySnap.data() ?? {};
      _isPremium = PremiumAccessService.isPremiumActiveFromData(myData);
      _isMaster = myData['isMaster'] == true;

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

        final country = (data['country'] ?? '').toString().trim().toLowerCase();

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
    // Franquia replyQuota substitui o timer/paywall legado nesta conversa.
    if (_usesReplyQuota) {
      _limitReached = false;
      _usageTimer?.cancel();
      _usageTimer = null;
      _remainingVN.value = 0;
      if (mounted) setState(() {});
      return;
    }

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
          debugPrint('Failed to save dailySecondsUsedWorld: $e');
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
      debugPrint('Failed to mark conversation as read: $e');
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
    _draftCodePoints = DmReplyQuota.countCodePoints(_textC.text);

    _setTyping(hasText);

    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 1200), () {
      _setTyping(false);
    });

    if (mounted) {
      setState(() {});
    }
  }

  // replyQuota: StreamBuilder(convDoc) no composer — sem listener adicional.
  String _otherFirstName() {
    final raw = widget.otherName.trim();
    if (raw.isEmpty) {
      return AppTexts.current.get('dm_quota_person_fallback');
    }
    return raw.split(RegExp(r'\s+')).first;
  }

  Future<void> _showQuotaExhaustedDialog() async {
    if (!mounted) return;
    await InternationalPremiumDialog.showQuotaExhausted(
      context,
      otherFirstName: _otherFirstName(),
    );
  }

  String _presenceLabel(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
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

  Future<bool> _ensureCanSendMessage({required bool showReplyModal}) async {
    final mySnap = await myUserDoc.get();
    final otherSnap = await otherUserDoc.get();
    final senderData = mySnap.data() ?? {};
    final recipientData = otherSnap.data() ?? {};
    final canSend = InternationalChatService.canSendMessage(
      senderData: senderData,
      recipientData: recipientData,
    );
    if (canSend) return true;

    // Free internacional: franquia 300 via Callable (não bloqueio total).
    final international = InternationalChatService.isInternational(
      InternationalChatService.readHomeCountryCode(senderData),
      InternationalChatService.readHomeCountryCode(recipientData),
    );
    if (international) {
      final q = _effectiveReplyQuota;
      if (q.exhausted) {
        if (showReplyModal && mounted) {
          await _showQuotaExhaustedDialog();
        }
        return false;
      }
      return true;
    }

    if (showReplyModal && mounted) {
      await InternationalPremiumDialog.showReply(context);
    }
    return false;
  }

  Future<bool> _ensureCanSendMedia() async {
    if (_usesReplyQuota) {
      if (mounted) {
        await _showQuotaExhaustedDialog();
      }
      return false;
    }
    return _ensureCanSendMessage(showReplyModal: true);
  }

  /// Atualiza resumo/unread sem reescrever `participants`/`pairKey`
  /// (a rule exige participants imutável — ordem diferente = permission-denied).
  Future<void> _updateConversationSummary({
    required String lastMessage,
    required String logPrefix,
  }) async {
    if (kDebugMode) {
      debugPrint(
          '$logPrefix: atualizando resumo da conversa path=conversations/${widget.conversationId}');
      debugPrint(
          '$logPrefix: campos={lastMessage,lastMessageAt,updatedAt,unread}');
    }

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
          'lastMessage': lastMessage,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'unread': unread,
        },
        SetOptions(merge: true),
      );
    });

    if (kDebugMode) {
      debugPrint('$logPrefix: resumo atualizado');
      debugPrint('$logPrefix: unread atualizado');
    }
  }

  Future<void> _send({String? retryMessageId}) async {
    final t = AppTexts.current;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    final isRetry = retryMessageId != null;
    late final String text;
    late final String pendingId;
    late final _PendingReplyData reply;

    if (isRetry) {
      final i = _pendingTexts.indexWhere((e) => e.pendingId == retryMessageId);
      if (i < 0) return;
      final item = _pendingTexts[i];
      if (!ChatMessageListStability.canStartRetry(
        failed: item.failed,
        sending: item.sending || _inFlightPendingIds.contains(item.pendingId),
      )) {
        return;
      }
      text = item.text;
      pendingId = item.pendingId;
      reply = item.reply;
      if (!_beginPendingSend(pendingId)) return;
      _patchPendingText(pendingId, failed: false, sending: true);
    } else {
      final mySnap =
          await FirebaseFirestore.instance.collection('users').doc(myUid).get();

      if (mySnap.data()?['shadowBan'] == true) {
        _warn(t.get('user_temporarily_silenced'));
        return;
      }

      if (!await _ensureCanSendMedia()) {
        return;
      }

      if (!_usesReplyQuota && _isWorldChat && _limitReached && !_isPremium) {
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

      text = _textC.text.trim();
      if (text.isEmpty) return;

      if (_containsPhone(text)) {
        _warn(t.get('chat_phone_not_allowed'));
        return;
      }

      if (_usesReplyQuota) {
        final q = _effectiveReplyQuota;
        final cost = DmReplyQuota.countCodePoints(text);
        if (cost > q.remaining) {
          if (mounted) setState(() {});
          await _showQuotaExhaustedDialog();
          return;
        }
      }

      _sending = true;
      _lastSentAt = now;
      pendingId = _makePendingId();
      reply = _captureReplyData();
      _textC.clear();
      _typingDebounce?.cancel();
      await _setTyping(false);
      _cancelReply();
      if (!_beginPendingSend(pendingId)) {
        _sending = false;
        return;
      }
      _addPendingText(pendingId: pendingId, text: text, reply: reply);
    }

    try {
      if (_usesReplyQuota) {
        final result = await SendDmMessageService().send(
          conversationId: widget.conversationId,
          otherUid: widget.otherUid,
          text: text,
          requestId: pendingId,
          messageId: pendingId,
          replyToMessageId: reply.replyToMessageId,
          replyToText: reply.replyToText,
          replyToType: reply.replyToType,
          replyToIsMe: reply.replyToIsMe,
        );
        if (!result.ok) {
          if (result.quota != null && mounted) {
            setState(() => _quotaFromCallable = result.quota!);
          }
          if (result.isQuotaExceeded) {
            _markPendingTextFailed(pendingId);
            await _showQuotaExhaustedDialog();
            return;
          }
          _markPendingTextFailed(pendingId);
          _notifySendFailed();
          return;
        }
        if (result.quota != null && mounted) {
          setState(() => _quotaFromCallable = result.quota!);
        }
        _patchPendingText(pendingId, sending: false);
        unawaited(
          LinkPreviewService.requestPreviewForMessage(
            text: text,
            messagePath:
                'conversations/${widget.conversationId}/messages/$pendingId',
          ),
        );
        // Unread/lastMessage: onPrivateMessageCreated no servidor.
        if (_scrollC.hasClients) {
          _scrollC.jumpTo(0);
        }
        return;
      }

      final clientNow = Timestamp.fromDate(DateTime.now());
      final msgData = <String, dynamic>{
        'type': 'text',
        'text': text,
        'senderId': myUid,
        'fromUid': myUid,
        'toUid': widget.otherUid,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': clientNow,
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
        'replyToMessageId': reply.replyToMessageId,
        'replyToText': reply.replyToText,
        'replyToType': reply.replyToType,
        'replyToIsMe': reply.replyToIsMe,
        'replyToImageUrl': reply.replyToImageUrl,
      };

      await msgsCol.doc(pendingId).set(msgData);
      _patchPendingText(pendingId, sending: false);

      // Prévia controlada — falha nunca impede mensagem já enviada.
      unawaited(
        LinkPreviewService.requestPreviewForMessage(
          text: text,
          messagePath:
              'conversations/${widget.conversationId}/messages/$pendingId',
        ),
      );

      try {
        await _updateConversationSummary(
          lastMessage: text,
          logPrefix: 'ChatText',
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('ChatText: falha parcial no resumo da conversa: $e\n$st');
        }
      }

      if (_scrollC.hasClients) {
        _scrollC.jumpTo(0);
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ChatText: erro ao enviar: $e\n$st');
      }
      _markPendingTextFailed(pendingId);
      _notifySendFailed();
    } finally {
      if (!isRetry) {
        _sending = false;
      }
      _endPendingSend(pendingId);
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
    required Map<String, dynamic> data,
    required bool isMe,
  }) {
    final t = AppTexts.current;
    final forwardable = canForwardMessageData(data);

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            if (forwardable)
              ListTile(
                leading: const Icon(Icons.shortcut, color: Color(0xFF313A5F)),
                title: Text(t.get('forward_action')),
                onTap: () {
                  Navigator.pop(context);
                  _openForward(messageId: messageId, data: data);
                },
              ),
            if (!isMe)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(t.get('report_message')),
                onTap: () {
                  Navigator.pop(context);
                  _openPrivateMessageReportSheet(messageId);
                },
              ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: Text(t.get('chat_delete_for_me')),
              onTap: () {
                Navigator.pop(context);
                _hideMessageForMe(messageId);
              },
            ),
            if (isMe)
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

  Future<void> _openForward({
    required String messageId,
    required Map<String, dynamic> data,
  }) async {
    if (!canForwardMessageData(data)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.current.get('forward_unavailable'))),
      );
      return;
    }
    final type = (data['type'] ?? 'text').toString();
    String preview = '';
    if (type == 'text') {
      preview = (data['text'] ?? '').toString();
    } else if (type == 'image') {
      preview = AppTexts.current.get('chat_photo_label');
    } else if (type == 'audio') {
      preview = AppTexts.current.get('chat_audio_label');
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForwardMessagePage(
          source: ForwardSource.dm(
            conversationId: widget.conversationId,
            messageId: messageId,
          ),
          previewLabel: preview,
        ),
      ),
    );
  }

  // =======================
  // ✅ ÁUDIO (UPLOAD + MSG + UNREAD + SCROLL)
  // =======================
  Future<void> _sendAudio(
    String localPath, {
    String? retryMessageId,
  }) async {
    final t = AppTexts.current;
    final sw = Stopwatch()..start();
    final isRetry = retryMessageId != null;

    late final String pendingId;
    late final _PendingReplyData reply;
    String? cachedUploadUrl;
    int? cachedDurationMs;
    var path = localPath;

    if (isRetry) {
      final i = _pendingAudios.indexWhere((e) => e.pendingId == retryMessageId);
      if (i < 0) return;
      final item = _pendingAudios[i];
      if (!ChatMessageListStability.canStartRetry(
        failed: item.failed,
        sending: item.sending || _inFlightPendingIds.contains(item.pendingId),
      )) {
        return;
      }
      pendingId = item.pendingId;
      path = item.localPath;
      reply = item.reply;
      cachedUploadUrl = item.uploadedUrl;
      cachedDurationMs = item.durationMs;
      if (!_beginPendingSend(pendingId)) return;
      _patchPendingAudio(pendingId, failed: false, sending: true);
    } else {
      if (kDebugMode) {
        debugPrint('ChatAudio: Mensagem/áudio send iniciado path=$localPath');
      }

      final mySnap = await myUserDoc.get();

      if (mySnap.data()?['shadowBan'] == true) {
        await _setRecording(false);
        _warn(t.get('user_temporarily_silenced'));
        return;
      }

      if (!await _ensureCanSendMessage(showReplyModal: true)) {
        await _setRecording(false);
        return;
      }

      if (!_usesReplyQuota && _isWorldChat && _limitReached && !_isPremium) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PremiumPage()),
        );
        return;
      }

      final blockedNow = await BlockService.isEitherBlocked(widget.otherUid);
      if (blockedNow) return;

      pendingId = _makePendingId();
      reply = _captureReplyData();
      if (!_beginPendingSend(pendingId)) return;
      _addPendingAudio(
        pendingId: pendingId,
        localPath: path,
        reply: reply,
      );
      _cancelReply();
    }

    try {
      var audioUrl = ChatMessageListStability.resolveUploadUrl(
        cachedUploadUrl: cachedUploadUrl,
      );
      var durationMs = cachedDurationMs ?? 0;

      if (audioUrl == null) {
        final file = File(path);
        if (!await file.exists()) {
          throw Exception('Arquivo de áudio não existe: $path');
        }

        var size = await file.length();
        if (size <= 0) {
          for (var i = 0; i < 15; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            size = await file.length();
            if (size > 0) break;
          }
        }
        if (size <= 0) {
          throw Exception('Arquivo de áudio vazio: $path');
        }
        if (kDebugMode) {
          debugPrint('ChatAudio: Arquivo pronto bytes=$size');
        }

        final probe = AudioPlayer();
        try {
          final d = await probe.setFilePath(path);
          durationMs = d?.inMilliseconds ?? 0;
          if (kDebugMode) {
            debugPrint('ChatAudio: Duração lida durationMs=$durationMs');
          }
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('ChatAudio: Erro ao ler duração: $e\n$st');
          }
        } finally {
          await probe.dispose();
        }

        if (kDebugMode) debugPrint('ChatAudio: Upload iniciado');
        final uploadSw = Stopwatch()..start();
        audioUrl = await _uploadAudioToStorage(path);
        uploadSw.stop();
        if (kDebugMode) {
          debugPrint(
            'ChatAudio: Upload concluído em ${uploadSw.elapsedMilliseconds}ms url=$audioUrl',
          );
        }
        _patchPendingAudio(
          pendingId,
          uploadedUrl: audioUrl,
          durationMs: durationMs,
        );
      } else if (kDebugMode) {
        debugPrint('ChatAudio: reutilizando upload existente');
      }

      if (kDebugMode) debugPrint('ChatAudio: salvando mensagem');
      final clientNow = Timestamp.fromDate(DateTime.now());
      await msgsCol.doc(pendingId).set({
        'type': 'audio',
        'audioUrl': audioUrl,
        'durationMs': durationMs,
        'senderId': myUid,
        'fromUid': myUid,
        'toUid': widget.otherUid,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': clientNow,
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
        'replyToMessageId': reply.replyToMessageId,
        'replyToText': reply.replyToText,
        'replyToType': reply.replyToType,
        'replyToIsMe': reply.replyToIsMe,
        'replyToImageUrl': reply.replyToImageUrl,
      });
      _patchPendingAudio(pendingId, sending: false);
      if (kDebugMode) debugPrint('ChatAudio: mensagem salva');

      try {
        await _updateConversationSummary(
          lastMessage: t.get('chat_audio_label'),
          logPrefix: 'ChatAudio',
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
            'ChatAudio: falha parcial no resumo da conversa '
            'path=conversations/${widget.conversationId}: $e\n$st',
          );
        }
      }

      if (_scrollC.hasClients) {
        _scrollC.jumpTo(0);
      }

      sw.stop();
      if (kDebugMode) {
        debugPrint(
          'ChatAudio: Envio completo em ${sw.elapsedMilliseconds}ms',
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ChatAudio: Erro completo ao enviar áudio: $e\n$st');
      }
      _markPendingAudioFailed(pendingId);
      _notifySendFailed();
    } finally {
      _endPendingSend(pendingId);
    }
  }

  Future<String> _uploadAudioToStorage(String localPath) async {
    final fileName = 'remdy_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final storagePath = 'chat_audio/${widget.conversationId}/$fileName';

    // A regra do Storage exige conversations/{id} com participants.
    final convSnap = await convDoc.get();
    if (!convSnap.exists) {
      throw Exception(
        'Conversa inexistente antes do upload de áudio: ${widget.conversationId}',
      );
    }

    if (kDebugMode) {
      debugPrint('ChatAudio: storagePath=$storagePath');
      debugPrint('ChatAudio: currentUid=$myUid');
      debugPrint('ChatAudio: conversationId=${widget.conversationId}');
    }

    final ref = FirebaseStorage.instance.ref().child(storagePath);

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

  Future<void> _sendImage(
    String localPath, {
    String? retryMessageId,
  }) async {
    final t = AppTexts.current;
    final isRetry = retryMessageId != null;

    late final String pendingId;
    late final _PendingReplyData reply;
    String? cachedUploadUrl;
    var path = localPath;

    if (isRetry) {
      final i = _pendingImages.indexWhere((e) => e.pendingId == retryMessageId);
      if (i < 0) return;
      final item = _pendingImages[i];
      if (!ChatMessageListStability.canStartRetry(
        failed: item.failed,
        sending: item.sending || _inFlightPendingIds.contains(item.pendingId),
      )) {
        return;
      }
      pendingId = item.pendingId;
      path = item.localPath;
      reply = item.reply;
      cachedUploadUrl = item.uploadedUrl;
      if (!_beginPendingSend(pendingId)) return;
      _patchPendingImage(pendingId, failed: false, sending: true);
    } else {
      final mySnap = await myUserDoc.get();

      if (mySnap.data()?['shadowBan'] == true) {
        _warn(t.get('user_temporarily_silenced'));
        return;
      }

      if (!await _ensureCanSendMedia()) {
        return;
      }

      if (!_usesReplyQuota && _isWorldChat && _limitReached && !_isPremium) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PremiumPage()),
        );
        return;
      }

      final blockedNow = await BlockService.isEitherBlocked(widget.otherUid);
      if (blockedNow) return;

      pendingId = _makePendingId();
      reply = _captureReplyData();
      if (!_beginPendingSend(pendingId)) return;
      _addPendingImage(
        pendingId: pendingId,
        localPath: path,
        reply: reply,
      );
      _cancelReply();
    }

    try {
      var imageUrl = ChatMessageListStability.resolveUploadUrl(
        cachedUploadUrl: cachedUploadUrl,
      );

      if (imageUrl == null) {
        final file = File(path);
        if (!await file.exists()) {
          _warn(t.get('chat_image_not_found'));
          _markPendingImageFailed(pendingId);
          return;
        }

        final size = await file.length();
        if (size <= 0) {
          _warn(t.get('chat_empty_image'));
          _markPendingImageFailed(pendingId);
          return;
        }

        imageUrl = await _uploadImageToStorage(path);
        _patchPendingImage(pendingId, uploadedUrl: imageUrl);
      } else if (kDebugMode) {
        debugPrint('ChatImage: reutilizando upload existente');
      }

      final clientNow = Timestamp.fromDate(DateTime.now());
      await msgsCol.doc(pendingId).set({
        'type': 'image',
        'imageUrl': imageUrl,
        'senderId': myUid,
        'fromUid': myUid,
        'toUid': widget.otherUid,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': clientNow,
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
        'hiddenFor': <String>[],
        'replyToMessageId': reply.replyToMessageId,
        'replyToText': reply.replyToText,
        'replyToType': reply.replyToType,
        'replyToIsMe': reply.replyToIsMe,
        'replyToImageUrl': reply.replyToImageUrl,
      });
      _patchPendingImage(pendingId, sending: false);

      try {
        await _updateConversationSummary(
          lastMessage: t.get('chat_photo_label'),
          logPrefix: 'ChatImage',
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('ChatImage: falha parcial no resumo da conversa: $e\n$st');
        }
      }

      if (_scrollC.hasClients) {
        _scrollC.jumpTo(0);
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ChatImage: erro ao enviar imagem: $e\n$st');
      }
      _markPendingImageFailed(pendingId);
      _notifySendFailed();
    } finally {
      _endPendingSend(pendingId);
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
    if (_usesReplyQuota) {
      _showQuotaExhaustedDialog();
      return;
    }

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

    AppNotificationState.instance.enterPrivateChat(widget.conversationId);

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
    AppNotificationState.instance.leavePrivateChat(widget.conversationId);

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
    FocusManager.instance.primaryFocus?.unfocus();
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

  Future<void> _sendChatReport(
    BuildContext context,
    ReportCategory category, {
    String? messageId,
  }) async {
    final t = AppTexts.current;
    try {
      await FirebaseFirestore.instance.collection('reports').add({
        'fromUid': myUid,
        'reportedUid': widget.otherUid,
        'reason': t.get(category.labelKey),
        ...reportClassification(category),
        'status': 'open',
        'contextType': messageId == null ? 'dm' : 'dm_message',
        'conversationId': widget.conversationId,
        if (messageId != null) 'messageId': messageId,
        'source': 'chat_page',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            category.isChildSafety
                ? t.get('report_child_safety_authorities_notice')
                : t.get('report_sent'),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
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
              leading:
                  const Icon(Icons.priority_high, color: Color(0xFFB91C1C)),
              title: Text(t.get(ReportCategory.childSafety.labelKey)),
              onTap: () {
                Navigator.pop(context);
                _sendChatReport(context, ReportCategory.childSafety);
              },
            ),
            ListTile(
              title: Text(t.get('report_reason_inappropriate')),
              onTap: () {
                Navigator.pop(context);
                _sendChatReport(context, ReportCategory.inappropriate);
              },
            ),
            ListTile(
              title: Text(t.get('report_reason_spam')),
              onTap: () {
                Navigator.pop(context);
                _sendChatReport(context, ReportCategory.spam);
              },
            ),
            ListTile(
              title: Text(t.get('report_reason_harassment')),
              onTap: () {
                Navigator.pop(context);
                _sendChatReport(context, ReportCategory.harassment);
              },
            ),
            ListTile(
              title: Text(t.get('report_reason_threat')),
              onTap: () {
                Navigator.pop(context);
                _sendChatReport(context, ReportCategory.threat);
              },
            ),
            ListTile(
              title: Text(t.get('report_reason_other')),
              onTap: () {
                Navigator.pop(context);
                _sendChatReport(context, ReportCategory.other);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openPrivateMessageReportSheet(String messageId) {
    final t = AppTexts.current;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading:
                  const Icon(Icons.priority_high, color: Color(0xFFB91C1C)),
              title: Text(t.get(ReportCategory.childSafety.labelKey)),
              onTap: () {
                Navigator.pop(context);
                _sendChatReport(
                  context,
                  ReportCategory.childSafety,
                  messageId: messageId,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(t.get(ReportCategory.inappropriate.labelKey)),
              onTap: () {
                Navigator.pop(context);
                _sendChatReport(
                  context,
                  ReportCategory.inappropriate,
                  messageId: messageId,
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
      resizeToAvoidBottomInset: true,
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
                decoration: InputDecoration(
                  hintText: t.get('chat_search_message_hit'),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchText = value.trim().toLowerCase();
                  });
                },
                style: TextStyle(
                  // ⚠️ tira o const aqui
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
                      final photoUrl = (data['photoUrl'] ??
                              data['photoURL'] ??
                              data['photo'] ??
                              '')
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
                                    ? widget.otherName
                                        .substring(0, 1)
                                        .toUpperCase()
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
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

                final locked = isBlocked;

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
                                if (snap.hasError) {
                                  return Center(
                                    child: Text(
                                      '${t.get('chat_error_prefix')} ${snap.error}',
                                    ),
                                  );
                                }

                                if (snap.hasData) {
                                  _cachedMsgDocs = snap.data!.docs;
                                } else if (_cachedMsgDocs.isEmpty) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }

                                final docs = _cachedMsgDocs;
                                final serverIds = docs.map((d) => d.id).toSet();
                                _syncPendingWithServerIds(serverIds);
                                final pendingItems =
                                    _buildPendingItems(serverIds);
                                final totalCount =
                                    pendingItems.length + docs.length;

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
                                      final key = ValueKey(
                                        ChatMessageListStability.bubbleKey(
                                          pending.pendingId,
                                        ),
                                      );

                                      if (pending.type == 'audio') {
                                        return KeyedSubtree(
                                          key: key,
                                          child: _AudioSendingBubble(
                                            isMe: true,
                                            failed: pending.failed,
                                            onRetry: pending.failed &&
                                                    !pending.sending
                                                ? () => _retryPendingAudio(
                                                      pending.pendingId,
                                                    )
                                                : null,
                                          ),
                                        );
                                      }

                                      if (pending.type == 'text') {
                                        return KeyedSubtree(
                                          key: key,
                                          child: _TextSendingBubble(
                                            isMe: true,
                                            text: pending.text,
                                            failed: pending.failed,
                                            onRetry: pending.failed &&
                                                    !pending.sending
                                                ? () => _retryPendingText(
                                                      pending.pendingId,
                                                    )
                                                : null,
                                          ),
                                        );
                                      }

                                      return KeyedSubtree(
                                        key: key,
                                        child: _ImageSendingBubble(
                                          isMe: true,
                                          localPath: pending.localPath,
                                          failed: pending.failed,
                                          onRetry:
                                              pending.failed && !pending.sending
                                                  ? () => _retryPendingImage(
                                                        pending.pendingId,
                                                      )
                                                  : null,
                                        ),
                                      );
                                    }

                                    final docIndex = i - pendingItems.length;

                                    if (docIndex < 0 ||
                                        docIndex >= docs.length) {
                                      return const SizedBox.shrink();
                                    }

                                    final d = docs[docIndex].data();
                                    final messageId = docs[docIndex].id;
                                    final bubbleKey = ValueKey(
                                      ChatMessageListStability.bubbleKey(
                                        messageId,
                                      ),
                                    );

                                    final textSearch = (d['text'] ?? '')
                                        .toString()
                                        .toLowerCase();

                                    if (_searchMode && _searchText.isNotEmpty) {
                                      if (!textSearch.contains(_searchText)) {
                                        return const SizedBox(height: 0);
                                      }
                                    }

                                    final msg = {
                                      ...d,
                                      'id': messageId,
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
                                    final clientCreatedAt =
                                        d['clientCreatedAt'] as Timestamp?;
                                    final timeText = _formatTime(
                                      createdAt ?? clientCreatedAt,
                                    );

                                    if (type == 'audio') {
                                      if (deleted) {
                                        return KeyedSubtree(
                                          key: bubbleKey,
                                          child: _Bubble(
                                            text: t.get('chat_audio_deleted'),
                                            isMe: isMe,
                                            isDeleted: true,
                                            timeText: timeText,
                                            replyToText: '',
                                            replyToType: 'text',
                                            replyToIsMe: false,
                                            replyToImageUrl: replyToImageUrl,
                                          ),
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
                                        key: bubbleKey,
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
                                          _openMessageActions(
                                            messageId: messageId,
                                            data: Map<String, dynamic>.from(d),
                                            isMe: isMe,
                                          );
                                        },
                                        child: AudioBubble(
                                          key: ValueKey(messageId),
                                          messageId: messageId,
                                          audioUrl: url,
                                          isMe: isMe,
                                          durationMs: durationMs,
                                          timeText: timeText,
                                          forwarded: d['forwarded'] == true,
                                        ),
                                      );
                                    }

                                    if (type == 'image') {
                                      if (deleted) {
                                        return KeyedSubtree(
                                          key: bubbleKey,
                                          child: _Bubble(
                                            text: t.get('chat_photo_deleted'),
                                            isMe: isMe,
                                            isDeleted: true,
                                            timeText: timeText,
                                            replyToText: '',
                                            replyToType: 'text',
                                            replyToIsMe: false,
                                            replyToImageUrl: replyToImageUrl,
                                          ),
                                        );
                                      }

                                      final imageUrl =
                                          (d['imageUrl'] ?? '').toString();

                                      return GestureDetector(
                                        key: bubbleKey,
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
                                          _openMessageActions(
                                            messageId: messageId,
                                            data: Map<String, dynamic>.from(d),
                                            isMe: isMe,
                                          );
                                        },
                                        child: _ImageBubble(
                                          imageUrl: imageUrl,
                                          isMe: isMe,
                                          timeText: timeText,
                                          forwarded: d['forwarded'] == true,
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
                                      return KeyedSubtree(
                                        key: bubbleKey,
                                        child: _Bubble(
                                          text: t.get('chat_message_deleted'),
                                          isMe: isMe,
                                          isDeleted: true,
                                          timeText: timeText,
                                          replyToText: '',
                                          replyToType: 'text',
                                          replyToIsMe: false,
                                          replyToImageUrl: '',
                                        ),
                                      );
                                    }

                                    final showDate =
                                        _shouldShowDateHeader(docs, docIndex);

                                    return Column(
                                      key: bubbleKey,
                                      children: [
                                        if (showDate)
                                          _DateHeader(
                                            label: _formatDayLabel(
                                              createdAt ?? clientCreatedAt,
                                            ),
                                          ),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            if (!_searchMode) return;

                                            _handleReplyFromMessage(
                                                msg, 'text');

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
                                              _handleReplyFromMessage(
                                                  msg, 'text');
                                            }
                                            _dragDx = 0;
                                          },
                                          onHorizontalDragCancel: () {
                                            _dragDx = 0;
                                          },
                                          onLongPress: () {
                                            _openMessageActions(
                                              messageId: messageId,
                                              data:
                                                  Map<String, dynamic>.from(d),
                                              isMe: isMe,
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
                                            forwarded: d['forwarded'] == true,
                                            linkPreview:
                                                LinkPreviewData.fromMap(
                                              d['linkPreview'],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: convDoc.snapshots(),
                      builder: (context, convSnap) {
                        final quota =
                            _effectiveReplyQuotaFrom(convSnap.data?.data());
                        final draftOver =
                            _usesReplyQuota && quota.draftExceeds(_textC.text);
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_usesReplyQuota)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Text(
                                  t.get('dm_quota_hint'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            else if (_isWorldChat && !_isPremium)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Text(
                                  t.get('chat_world_is_premium'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            SafeArea(
                              top: false,
                              minimum: EdgeInsets.zero,
                              child: Container(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                decoration: BoxDecoration(
                                  color: _card,
                                  border:
                                      Border(top: BorderSide(color: _border)),
                                ),
                                child: Column(
                                  children: [
                                    if (_replyToMessageId != null)
                                      Container(
                                        width: double.infinity,
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF3F4F6),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border(
                                            left: BorderSide(
                                              color: _replyToIsMe
                                                  ? _remdyBlue
                                                  : _muted,
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
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: _text,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  if (_replyToType == 'image' &&
                                                      _replyToImageUrl
                                                          .isNotEmpty)
                                                    Row(
                                                      children: [
                                                        ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6),
                                                          child: Image.network(
                                                            _replyToImageUrl,
                                                            width: 42,
                                                            height: 42,
                                                            fit: BoxFit.cover,
                                                            errorBuilder:
                                                                (_, __, ___) =>
                                                                    Container(
                                                              width: 42,
                                                              height: 42,
                                                              color: const Color(
                                                                  0xFFE5E7EB),
                                                              alignment:
                                                                  Alignment
                                                                      .center,
                                                              child: const Icon(
                                                                  Icons.image,
                                                                  size: 18),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            t.get(
                                                                'chat_photo_label'),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
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
                                                          ? t.get(
                                                              'chat_audio_label')
                                                          : _replyToType ==
                                                                  'image'
                                                              ? t.get(
                                                                  'chat_photo_label')
                                                              : _replyToText,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
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
                                              icon: const Icon(Icons.close,
                                                  size: 18),
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
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                color: draftOver
                                                    ? const Color(0xFFDC2626)
                                                    : _border,
                                              ),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14),
                                            child: TextField(
                                              controller: _textC,
                                              enabled: !isBlocked,
                                              textInputAction:
                                                  TextInputAction.send,
                                              onSubmitted: (_) async {
                                                if (isBlocked) return;
                                                await _setTyping(false);
                                                await _send();
                                              },
                                              decoration: InputDecoration(
                                                hintText: isBlocked
                                                    ? t.get(
                                                        'chat_cannot_send_blocked')
                                                    : t.get(
                                                        'chat_type_message'),
                                                border: InputBorder.none,
                                                suffixIcon: _usesReplyQuota
                                                    ? Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(right: 4),
                                                        child: Center(
                                                          widthFactor: 1,
                                                          child: Text(
                                                            '${quota.used + (_textC.text.isEmpty ? 0 : _draftCodePoints)}/${quota.limit}',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: draftOver
                                                                  ? const Color(
                                                                      0xFFDC2626)
                                                                  : _muted,
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                    : null,
                                                suffixIconConstraints:
                                                    const BoxConstraints(
                                                  minWidth: 0,
                                                  minHeight: 0,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Opacity(
                                          opacity: locked ? 0.45 : 1.0,
                                          child: InkWell(
                                            onTap: isBlocked
                                                ? null
                                                : _openPlusMenu,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            child: Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border:
                                                    Border.all(color: _border),
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
                                                  ignoring: isBlocked,
                                                  child: RecordingButton(
                                                    onRecordStart: () async {
                                                      await _setRecording(true);
                                                    },
                                                    onRecordStop: () async {
                                                      await _setRecording(
                                                          false);
                                                    },
                                                    onRecorded: (path) async {
                                                      await _setRecording(
                                                          false);

                                                      if (path == null) return;

                                                      await _sendAudio(path);
                                                    },
                                                  ),
                                                ),
                                              )
                                            : Opacity(
                                                opacity: isBlocked ? 0.45 : 1.0,
                                                child: InkWell(
                                                  onTap:
                                                      isBlocked ? null : _send,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                  child: Container(
                                                    width: 40,
                                                    height: 40,
                                                    decoration: BoxDecoration(
                                                      gradient:
                                                          const LinearGradient(
                                                        colors: [
                                                          _remdyBlue,
                                                          _logoBlue
                                                        ],
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              999),
                                                      boxShadow: const [
                                                        BoxShadow(
                                                          color:
                                                              Color(0x14000000),
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

class _PendingReplyData {
  final String? replyToMessageId;
  final String replyToText;
  final String replyToType;
  final bool replyToIsMe;
  final String replyToImageUrl;

  const _PendingReplyData({
    required this.replyToMessageId,
    required this.replyToText,
    required this.replyToType,
    required this.replyToIsMe,
    required this.replyToImageUrl,
  });
}

class _PendingAudioItem {
  final String pendingId;
  final String localPath;
  final DateTime createdAt;
  final bool failed;
  final bool sending;
  final String? uploadedUrl;
  final int? durationMs;
  final _PendingReplyData reply;

  const _PendingAudioItem({
    required this.pendingId,
    required this.localPath,
    required this.createdAt,
    required this.reply,
    this.failed = false,
    this.sending = false,
    this.uploadedUrl,
    this.durationMs,
  });

  _PendingAudioItem copyWith({
    bool? failed,
    bool? sending,
    String? uploadedUrl,
    int? durationMs,
  }) {
    return _PendingAudioItem(
      pendingId: pendingId,
      localPath: localPath,
      createdAt: createdAt,
      reply: reply,
      failed: failed ?? this.failed,
      sending: sending ?? this.sending,
      uploadedUrl: uploadedUrl ?? this.uploadedUrl,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}

class _PendingImageItem {
  final String pendingId;
  final String localPath;
  final DateTime createdAt;
  final bool failed;
  final bool sending;
  final String? uploadedUrl;
  final _PendingReplyData reply;

  const _PendingImageItem({
    required this.pendingId,
    required this.localPath,
    required this.createdAt,
    required this.reply,
    this.failed = false,
    this.sending = false,
    this.uploadedUrl,
  });

  _PendingImageItem copyWith({
    bool? failed,
    bool? sending,
    String? uploadedUrl,
  }) {
    return _PendingImageItem(
      pendingId: pendingId,
      localPath: localPath,
      createdAt: createdAt,
      reply: reply,
      failed: failed ?? this.failed,
      sending: sending ?? this.sending,
      uploadedUrl: uploadedUrl ?? this.uploadedUrl,
    );
  }
}

class _PendingTextItem {
  final String pendingId;
  final String text;
  final DateTime createdAt;
  final bool failed;
  final bool sending;
  final _PendingReplyData reply;

  const _PendingTextItem({
    required this.pendingId,
    required this.text,
    required this.createdAt,
    required this.reply,
    this.failed = false,
    this.sending = false,
  });

  _PendingTextItem copyWith({
    bool? failed,
    bool? sending,
  }) {
    return _PendingTextItem(
      pendingId: pendingId,
      text: text,
      createdAt: createdAt,
      reply: reply,
      failed: failed ?? this.failed,
      sending: sending ?? this.sending,
    );
  }
}

class _PendingChatListItem {
  final String pendingId;
  final String type;
  final DateTime createdAt;
  final String localPath;
  final String text;
  final bool failed;
  final bool sending;

  const _PendingChatListItem._({
    required this.pendingId,
    required this.type,
    required this.createdAt,
    required this.localPath,
    required this.text,
    required this.failed,
    required this.sending,
  });

  factory _PendingChatListItem.audio({
    required String pendingId,
    required DateTime createdAt,
    required String localPath,
    bool failed = false,
    bool sending = false,
  }) {
    return _PendingChatListItem._(
      pendingId: pendingId,
      type: 'audio',
      createdAt: createdAt,
      localPath: localPath,
      text: '',
      failed: failed,
      sending: sending,
    );
  }

  factory _PendingChatListItem.image({
    required String pendingId,
    required DateTime createdAt,
    required String localPath,
    bool failed = false,
    bool sending = false,
  }) {
    return _PendingChatListItem._(
      pendingId: pendingId,
      type: 'image',
      createdAt: createdAt,
      localPath: localPath,
      text: '',
      failed: failed,
      sending: sending,
    );
  }

  factory _PendingChatListItem.text({
    required String pendingId,
    required DateTime createdAt,
    required String text,
    bool failed = false,
    bool sending = false,
  }) {
    return _PendingChatListItem._(
      pendingId: pendingId,
      type: 'text',
      createdAt: createdAt,
      localPath: '',
      text: text,
      failed: failed,
      sending: sending,
    );
  }
}

class _TextSendingBubble extends StatelessWidget {
  final bool isMe;
  final String text;
  final bool failed;
  final VoidCallback? onRetry;

  const _TextSendingBubble({
    required this.isMe,
    required this.text,
    this.failed = false,
    this.onRetry,
  });

  static const Color _textColor = Color(0xFF111827);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final bg = isMe ? _remdyBlue : Colors.white;
    final fg = isMe ? Colors.white : _textColor;

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
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(color: fg, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!failed)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isMe ? Colors.white : _remdyBlue,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: isMe ? Colors.white : Colors.redAccent,
                  ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    failed
                        ? t.get('chat_send_failed')
                        : t.get('chat_sending_message'),
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (failed && onRetry != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: fg,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(t.get('chat_retry_send')),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioSendingBubble extends StatelessWidget {
  final bool isMe;
  final bool failed;
  final VoidCallback? onRetry;

  const _AudioSendingBubble({
    required this.isMe,
    this.failed = false,
    this.onRetry,
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
            if (!failed)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isMe ? Colors.white : _remdyBlue,
                  ),
                ),
              )
            else
              Icon(
                Icons.error_outline,
                size: 18,
                color: isMe ? Colors.white : Colors.redAccent,
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                failed
                    ? t.get('chat_send_failed')
                    : t.get('chat_sending_audio'),
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            if (failed && onRetry != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: fg,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(t.get('chat_retry_send')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImageSendingBubble extends StatelessWidget {
  final bool isMe;
  final String localPath;
  final bool failed;
  final VoidCallback? onRetry;

  const _ImageSendingBubble({
    required this.isMe,
    required this.localPath,
    this.failed = false,
    this.onRetry,
  });

  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final hasLocal = localPath.isNotEmpty && File(localPath).existsSync();

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
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 200,
                height: 200,
                child: hasLocal
                    ? Image.file(
                        File(localPath),
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: isMe
                            ? Colors.white.withOpacity(0.10)
                            : const Color(0xFFF1F5F9),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_outlined,
                          size: 42,
                          color: Colors.white70,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!failed)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isMe ? Colors.white : _remdyBlue,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: isMe ? Colors.white : Colors.redAccent,
                  ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    failed
                        ? t.get('chat_send_failed')
                        : t.get('chat_sending_image'),
                    style: TextStyle(
                      color: isMe ? Colors.white : const Color(0xFF111827),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (failed && onRetry != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor:
                          isMe ? Colors.white : const Color(0xFF111827),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(t.get('chat_retry_send')),
                  ),
                ],
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
  final bool forwarded;

  const _ImageBubble({
    required this.imageUrl,
    required this.isMe,
    required this.timeText,
    this.forwarded = false,
  });

  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
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
              if (forwarded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    t.get('forward_label'),
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: isMe ? Colors.white70 : const Color(0xFF6B7280),
                    ),
                  ),
                ),
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
  final LinkPreviewData? linkPreview;
  final bool forwarded;

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
    this.linkPreview,
    this.forwarded = false,
  });

  static const Color _text = Color(0xFF111827);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final bg = isMe ? _remdyBlue : Colors.white;
    final fg = isMe ? Colors.white : _text;
    final textStyle = TextStyle(
      color: isDeleted ? (isMe ? Colors.white70 : const Color(0xFF6B7280)) : fg,
      fontWeight: FontWeight.w600,
      fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
      fontSize: isDeleted ? 12.5 : 14,
      height: 1.25,
    );

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
            if (forwarded && !isDeleted)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  t.get('forward_label'),
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: isMe ? Colors.white70 : const Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
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
                    else if (replyToType == 'image' &&
                        replyToImageUrl.isNotEmpty)
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
                                color: isMe
                                    ? Colors.white70
                                    : const Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      MessageTextWithLinks(
                        text: replyToType == 'audio'
                            ? t.get('chat_audio_label')
                            : replyToType == 'image'
                                ? t.get('chat_photo_label')
                                : replyToText,
                        enabled: !isDeleted && replyToType == 'text',
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              isMe ? Colors.white70 : const Color(0xFF6B7280),
                        ),
                        linkStyle: TextStyle(
                          fontSize: 13,
                          color: isMe ? Colors.white : const Color(0xFF1D4ED8),
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            MessageTextWithLinks(
              text: text,
              enabled: !isDeleted,
              style: textStyle,
              linkStyle: textStyle.copyWith(
                decoration: TextDecoration.underline,
                color: isMe ? Colors.white : const Color(0xFF1D4ED8),
              ),
            ),
            if (!isDeleted && linkPreview != null)
              LinkPreviewCard(data: linkPreview!, isMe: isMe),
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
                decoration: InputDecoration(
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
                  return Center(
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
                  return Center(
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
                  return Center(
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
