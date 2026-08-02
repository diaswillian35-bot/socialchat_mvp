import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import '../l10n/app_texts.dart';
import '../pages/forward_message_page.dart';
import '../services/forward_message_service.dart';
import '../services/group_ban_service.dart';
import '../services/group_join_service.dart';
import '../services/group_join_ui_logic.dart';
import '../services/group_read_service.dart';
import '../services/premium_access_service.dart';
import '../utils/chat_message_list_stability.dart';
import '../services/app_notification_state.dart';
import '../services/online_status.dart';
import '../services/presence_rtdb_config.dart';
import '../services/presence_rtdb_logic.dart';
import '../services/presence_watch.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'group_info_page.dart';
import '../widget/audio_bubble.dart';
import '../widget/recording_button.dart';
import '../widgets/message_text_with_links.dart';
import '../widgets/link_preview_card.dart';
import '../services/link_preview_service.dart';
import '../widgets/international_premium_dialog.dart';

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

  String? _replyToMessageId;
  String _replyToText = '';
  String _replyToType = 'text';
  bool _replyToIsMe = false;
  String _replyToImageUrl = '';
  double _dragDx = 0;

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
  bool _isMaster = false;
  bool _isWorldGroup = false;

  String _myCountryCode = '';
  String _groupCountryCode = '';

  bool _booting = true;
  bool _didInitialRead = false;
  bool _isMember = false;
  bool _previewMode = false;
  bool _isBanned = false;
  bool _joining = false;
  bool _handledGroupUnavailable = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _groupWatchSub;

  Map<String, dynamic>? _groupData;

  final Map<String, Map<String, dynamic>> _userCache = {};
  final Set<String> _loadingUserIds = {};

  final List<_PendingAudioItem> _pendingAudios = [];
  final List<_PendingImageItem> _pendingImages = [];
  final List<_PendingTextItem> _pendingTexts = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _cachedMsgDocs = const [];
  final Set<String> _inFlightPendingIds = {};

  int _lastRenderedCount = 0;

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
      idOf: (_PendingAudioItem e) => e.localId,
      serverIds: serverIds,
    );
    final nextImages =
        ChatMessageListStability.pruneConfirmedPending<_PendingImageItem>(
      pending: _pendingImages,
      idOf: (_PendingImageItem e) => e.localId,
      serverIds: serverIds,
    );
    final nextTexts =
        ChatMessageListStability.pruneConfirmedPending<_PendingTextItem>(
      pending: _pendingTexts,
      idOf: (_PendingTextItem e) => e.localId,
      serverIds: serverIds,
    );
    if (nextAudios.length == _pendingAudios.length &&
        nextImages.length == _pendingImages.length &&
        nextTexts.length == _pendingTexts.length) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
      final i = _pendingAudios.indexWhere((e) => e.localId == pendingId);
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
      final i = _pendingImages.indexWhere((e) => e.localId == pendingId);
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
      final i = _pendingTexts.indexWhere((e) => e.localId == pendingId);
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

  void _notifySendFailed() {
    if (!mounted) return;
    _toast(AppTexts.current.get('chat_send_failed'));
  }

  Future<void> _retryPendingAudio(String pendingId) async {
    final i = _pendingAudios.indexWhere((e) => e.localId == pendingId);
    if (i < 0) return;
    final item = _pendingAudios[i];
    if (!ChatMessageListStability.canStartRetry(
      failed: item.failed,
      sending: item.sending || _inFlightPendingIds.contains(pendingId),
    )) {
      return;
    }
    final path = item.localPath;
    if (path == null || path.isEmpty) return;
    await _sendGroupAudioMessage(path, retryMessageId: pendingId);
  }

  Future<void> _retryPendingImage(String pendingId) async {
    final i = _pendingImages.indexWhere((e) => e.localId == pendingId);
    if (i < 0) return;
    final item = _pendingImages[i];
    if (!ChatMessageListStability.canStartRetry(
      failed: item.failed,
      sending: item.sending || _inFlightPendingIds.contains(pendingId),
    )) {
      return;
    }
    await _sendGroupImageMessage(item.localPath, retryMessageId: pendingId);
  }

  Future<void> _retryPendingText(String pendingId) async {
    final i = _pendingTexts.indexWhere((e) => e.localId == pendingId);
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

  @override
  void initState() {
    super.initState();
    _textC.addListener(_onTextChanged);
    AppNotificationState.instance.enterGroupChat(widget.groupId);
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
    AppNotificationState.instance.leaveGroupChat(widget.groupId);
    _groupWatchSub?.cancel();
    _typingDebounce?.cancel();
    _setTyping(false);
    _setRecording(false);
    _textC.removeListener(_onTextChanged);
    _textC.dispose();
    _searchController.dispose();
    _scrollC.dispose();
    FocusManager.instance.primaryFocus?.unfocus();

    super.dispose();
  }

  void _watchGroupDoc() {
    _groupWatchSub?.cancel();
    _groupWatchSub = _groupRef.snapshots().listen((snap) async {
      if (!mounted || _handledGroupUnavailable) return;

      final data = snap.data();
      if (data == null) return;

      _groupData = data;
      final myUid = uid;
      final deleted = data['deleted'] == true;

      final membersRaw = data['members'];
      final members = (membersRaw is List)
          ? membersRaw.map((e) => e.toString()).toList()
          : <String>[];
      final stillMember = myUid != null && members.contains(myUid);

      if (deleted || (myUid != null && !stillMember && _isMember)) {
        await _handleGroupAccessLost(deleted: deleted);
      }
    }, onError: (_) {});
  }

  Future<void> _handleGroupAccessLost({required bool deleted}) async {
    if (!mounted || _handledGroupUnavailable) return;
    _handledGroupUnavailable = true;

    final t = AppTexts.current;
    final myUid = uid;

    try {
      await _setTyping(false);
      await _setRecording(false);
      if (myUid != null) {
        await _presenceRef.doc(myUid).delete();
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _isMember = false;
      _previewMode = true;
      _canSend = false;
    });

    _toast(
      deleted
          ? t.get('group_no_longer_available')
          : t.get('youAreNoLongerInGroup'),
    );

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
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

      if (data['deleted'] == true) {
        await _handleGroupAccessLost(deleted: true);
        return;
      }

      final membersRaw = data['members'];
      final members = (membersRaw is List)
          ? membersRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : <String>[];

      final alreadyMember = members.contains(myUid);

      final banned = await GroupBanService.isUserBanned(
        groupId: widget.groupId,
        uid: myUid,
      );

      if (!mounted) return;
      setState(() {
        _isBanned = banned;
        _isMember = alreadyMember && !banned;
        _previewMode = !_isMember;
        _canSend = _isMember && !(_isWorldGroup && !_isPremium);
      });

      if (banned && mounted) {
        _toast(AppTexts.current.get('group_you_are_banned'));
      }
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

    if (!GroupJoinUiLogic.canStartJoin(
      isJoining: _joining,
      isBanned: _isBanned,
    )) {
      return;
    }

    if (myUid == null) {
      _toast(t.get('group_login_to_join'));
      return;
    }

    if (_isWorldGroup && !_isPremium) {
      final decision = GroupJoinUiLogic.premiumRequired();
      await _applyJoinDecision(decision);
      return;
    }

    setState(() => _joining = true);

    try {
      final result = await GroupJoinService.joinByGroupId(
        groupId: widget.groupId,
        uid: myUid,
      );

      if (!mounted) return;

      final decision = GroupJoinUiLogic.fromResult(result);
      await _applyJoinDecision(decision, result: result);
    } catch (e) {
      debugPrint('GroupChatPage._joinGroup unexpected: $e');
      if (!mounted) return;
      await _applyJoinDecision(GroupJoinUiLogic.fromUnexpected(e));
    } finally {
      // Garante liberação do botão mesmo com return antecipado / unmount.
      if (mounted && _joining) {
        setState(() => _joining = false);
      } else {
        _joining = false;
      }
    }
  }

  Future<void> _applyJoinDecision(
    GroupJoinUiDecision decision, {
    GroupJoinResult? result,
  }) async {
    final t = AppTexts.current;

    if (decision.debugDetail != null) {
      debugPrint(
        'GroupJoin detail [${decision.effect}]: ${decision.debugDetail}',
      );
    }

    switch (decision.effect) {
      case GroupJoinUiEffect.showJoining:
        return;

      case GroupJoinUiEffect.idle:
        return;

      case GroupJoinUiEffect.enterChat:
        // Atualiza a UI IMEDIATAMENTE — não espera markAsRead (callable).
        // Antes: await markAsRead bloqueava o setState e o spinner de
        // mensagens (PERMISSION_DENIED no preview) parecia eterno.
        setState(() {
          _isMember = true;
          _previewMode = false;
          _canSend = true;
          _didInitialRead = true;
          _isBanned = false;
        });
        if (result?.outcome == GroupJoinOutcome.joined &&
            decision.messageKey != null) {
          _toast(t.get(decision.messageKey!));
        }
        final gid = result?.groupId ?? widget.groupId;
        // Fire-and-forget: falha de leitura não deve reter o usuário.
        unawaited(
          GroupReadService.markAsRead(groupId: gid).catchError((Object e) {
            debugPrint('markAsRead after join: $e');
          }),
        );
        return;

      case GroupJoinUiEffect.showPending:
        _toast(
          t.get(
            decision.messageKey ??
                (result?.outcome == GroupJoinOutcome.pendingExists
                    ? 'group_awaiting_approval'
                    : 'group_request_sent_to_admin'),
          ),
        );
        return;

      case GroupJoinUiEffect.showBanned:
        setState(() {
          _isBanned = true;
          _isMember = false;
          _previewMode = true;
          _canSend = false;
        });
        _toast(t.get(decision.messageKey ?? 'group_cannot_join_banned'));
        return;

      case GroupJoinUiEffect.showPremiumRequired:
        await InternationalPremiumDialog.showStart(context);
        return;

      case GroupJoinUiEffect.showInviteOnly:
      case GroupJoinUiEffect.showUnavailable:
      case GroupJoinUiEffect.showLoginRequired:
        _toast(t.get(decision.messageKey ?? 'group_unavailable'));
        return;

      case GroupJoinUiEffect.showNetworkError:
        _toast(t.get(decision.messageKey ?? 'group_join_network_error'));
        return;

      case GroupJoinUiEffect.showGenericError:
        // Detalhes técnicos apenas em builds de debug.
        final detail = kDebugMode ? decision.debugDetail : null;
        _toast(
          detail == null || detail.isEmpty
              ? t.get(decision.messageKey ?? 'group_error_join_prefix')
              : '${t.get(decision.messageKey ?? 'group_error_join_prefix')} $detail'
                  .trim(),
        );
        return;
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

      final premiumActive =
          PremiumAccessService.isPremiumActiveFromData(myData);
      final master = myData['isMaster'] == true;

      final groupData = _groupData ?? (await _groupRef.get()).data() ?? {};
      final groupCountry = _normalizeCountry(
        (groupData['countryCode'] ?? groupData['country'] ?? '').toString(),
      );

      if (!mounted) return;
      setState(() {
        _myCountryCode = myCountry;
        _groupCountryCode = groupCountry;
        _isPremium = premiumActive;
        _isMaster = master;

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
    _watchGroupDoc();

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

  Future<void> _reportMessage({
    required String messageId,
    required String reportedUid,
  }) async {
    final myUid = uid;
    if (myUid == null) return;

    await FirebaseFirestore.instance.collection('reports').add({
      'type': 'message',
      'contextType': 'group',
      'groupId': widget.groupId,
      'messageId': messageId,
      'reportedUid': reportedUid,
      'reporterUid': myUid,
      'fromUid': myUid,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });

    _toast(AppTexts.current.get('group_message_reported_success'));
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

  void _handleReplyFromMessage(Map<String, dynamic> d, String fallbackType) {
    final t = AppTexts.current;

    final senderId = (d['senderId'] ?? '').toString().trim();
    final isMe = senderId == uid;

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
    if (_membershipChecked) return;
    _membershipChecked = true;

    final myUid = uid;
    if (myUid == null) {
      if (!mounted) return;

      setState(() {
        _canSend = !(_isWorldGroup && !_isPremium);
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

      if (alreadyMember) {
        if (!mounted) return;
        setState(() => _canSend = true);
        return;
      }

      final policy = GroupJoinService.normalizeJoinPolicy(data['joinPolicy']);
      // Auto-join silencioso só para open (nunca inviteOnly/approval).
      if (policy != 'open') {
        if (!mounted) return;
        setState(() => _canSend = false);
        return;
      }

      final result = await GroupJoinService.joinByGroupId(
        groupId: widget.groupId,
        uid: myUid,
      );

      if (!mounted) return;
      setState(() => _canSend = result.didEnterChat);
    } catch (e) {
      debugPrint('Erro _ensureMemberIfAllowed: $e');
      if (!mounted) return;
      setState(() => _canSend = false);
    }
  }

  Future<void> _markGroupAsRead() async {
    final myUid = uid;
    if (myUid == null || !_isMember || _handledGroupUnavailable) return;

    try {
      await GroupReadService.markAsRead(groupId: widget.groupId);
    } on FirebaseFunctionsException catch (e) {
      // Silencioso se perdeu acesso; evita toast invasivo no open.
      if (e.code == 'permission-denied' || e.code == 'failed-precondition') {
        return;
      }
      debugPrint('markGroupAsRead: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('markGroupAsRead error: $e');
    }
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
    if (myUid == null || !_canSend || _handledGroupUnavailable) return;

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
    if (myUid == null || !_canSend || _handledGroupUnavailable) return;

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

  Future<void> _send({String? retryMessageId}) async {
    final myUid = uid;
    if (myUid == null || (!_canSend && retryMessageId == null)) return;

    final isRetry = retryMessageId != null;
    late final String text;
    late final String pendingId;
    late final _PendingReplyData reply;

    if (isRetry) {
      final i = _pendingTexts.indexWhere((e) => e.localId == retryMessageId);
      if (i < 0) return;
      final item = _pendingTexts[i];
      if (!ChatMessageListStability.canStartRetry(
        failed: item.failed,
        sending: item.sending || _inFlightPendingIds.contains(item.localId),
      )) {
        return;
      }
      text = item.text;
      pendingId = item.localId;
      reply = item.reply;
      if (!_beginPendingSend(pendingId)) return;
      _patchPendingText(pendingId, failed: false, sending: true);
    } else {
      final mySnap =
          await FirebaseFirestore.instance.collection('users').doc(myUid).get();
      if (mySnap.data()?['shadowBan'] == true) {
        _toast(AppTexts.current.get('user_temporarily_silenced'));
        return;
      }

      text = _textC.text.trim();
      if (text.isEmpty) return;

      pendingId = _msgsRef.doc().id;
      reply = _captureReplyData();
      _textC.clear();
      _typingDebounce?.cancel();
      await _setTyping(false);
      _cancelReply();
      if (!_beginPendingSend(pendingId)) return;
      if (mounted) {
        setState(() {
          _pendingTexts.insert(
            0,
            _PendingTextItem(
              localId: pendingId,
              senderId: myUid,
              text: text,
              createdAt: DateTime.now(),
              reply: reply,
              sending: true,
            ),
          );
        });
      }
    }

    try {
      final batch = FirebaseFirestore.instance.batch();
      final msgRef = _msgsRef.doc(pendingId);
      // clientCreatedAt is not in firestore.rules messageCreateKeysOk().
      batch.set(msgRef, {
        'id': pendingId,
        'type': 'text',
        'text': text,
        'senderId': myUid,
        'createdAt': FieldValue.serverTimestamp(),
        'replyToMessageId': reply.replyToMessageId,
        'replyToText': reply.replyToText,
        'replyToType': reply.replyToType,
        'replyToIsMe': reply.replyToIsMe,
        'replyToImageUrl': reply.replyToImageUrl,
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
      });

      final readRef = _groupRef.collection('reads').doc(myUid);
      batch.set(
        readRef,
        {
          'uid': myUid,
          'lastReadAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
      _patchPendingText(pendingId, sending: false);
      unawaited(
        LinkPreviewService.requestPreviewForMessage(
          text: text,
          messagePath: 'groups/${widget.groupId}/messages/$pendingId',
        ),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('GroupText: erro ao enviar: $e\n$st');
      }
      _markPendingTextFailed(pendingId);
      _notifySendFailed();
    } finally {
      _endPendingSend(pendingId);
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
      throw Exception(
          '${t.get('group_audio_file_not_found_prefix')} $localPath');
    }

    final size = await file.length();
    if (size <= 0) {
      throw Exception('${t.get('group_audio_file_empty_prefix')} $localPath');
    }

    final fileName =
        'audio_${DateTime.now().millisecondsSinceEpoch}_$myUid.m4a';

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

  Future<void> _sendGroupAudioMessage(
    String localPath, {
    String? retryMessageId,
  }) async {
    final t = AppTexts.current;
    final myUid = uid;
    if (myUid == null || (!_canSend && retryMessageId == null)) return;

    final isRetry = retryMessageId != null;
    late final String pendingId;
    late final _PendingReplyData reply;
    String? cachedUploadUrl;
    int? cachedDurationMs;
    var path = localPath;

    if (isRetry) {
      final i = _pendingAudios.indexWhere((e) => e.localId == retryMessageId);
      if (i < 0) return;
      final item = _pendingAudios[i];
      if (!ChatMessageListStability.canStartRetry(
        failed: item.failed,
        sending: item.sending || _inFlightPendingIds.contains(item.localId),
      )) {
        return;
      }
      pendingId = item.localId;
      path = item.localPath ?? localPath;
      reply = item.reply;
      cachedUploadUrl = item.uploadedUrl;
      cachedDurationMs = item.durationMs;
      if (!_beginPendingSend(pendingId)) return;
      _patchPendingAudio(pendingId, failed: false, sending: true);
    } else {
      final mySnap =
          await FirebaseFirestore.instance.collection('users').doc(myUid).get();

      if (mySnap.data()?['shadowBan'] == true) {
        _toast(AppTexts.current.get('user_temporarily_silenced'));
        return;
      }

      pendingId = _msgsRef.doc().id;
      reply = _captureReplyData();
      if (!_beginPendingSend(pendingId)) return;
      if (mounted) {
        setState(() {
          _pendingAudios.insert(
            0,
            _PendingAudioItem(
              localId: pendingId,
              senderId: myUid,
              createdAt: DateTime.now(),
              localPath: path,
              reply: reply,
              sending: true,
            ),
          );
        });
      }
      _cancelReply();
    }

    try {
      var audioUrl = ChatMessageListStability.resolveUploadUrl(
        cachedUploadUrl: cachedUploadUrl,
      );
      var durationMs = cachedDurationMs ?? 0;

      if (audioUrl == null) {
        final tmp = AudioPlayer();
        Duration? dur;
        try {
          await tmp.setFilePath(path);
          dur = tmp.duration;
        } catch (_) {}
        await tmp.dispose();
        durationMs = dur?.inMilliseconds ?? 0;

        audioUrl = await _uploadGroupAudioToStorage(
          groupId: widget.groupId,
          myUid: myUid,
          localPath: path,
        );
        _patchPendingAudio(
          pendingId,
          uploadedUrl: audioUrl,
          durationMs: durationMs,
        );
      } else if (kDebugMode) {
        debugPrint('GroupAudio: reutilizando upload existente');
      }

      final batch = FirebaseFirestore.instance.batch();
      final msgRef = _msgsRef.doc(pendingId);

      batch.set(msgRef, {
        'type': 'audio',
        'text': t.get('chat_audio_label'),
        'audioUrl': audioUrl,
        'durationMs': durationMs,
        'senderId': myUid,
        'createdAt': FieldValue.serverTimestamp(),
        'replyToMessageId': reply.replyToMessageId,
        'replyToText': reply.replyToText,
        'replyToType': reply.replyToType,
        'replyToIsMe': reply.replyToIsMe,
        'replyToImageUrl': reply.replyToImageUrl,
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
      });

      final readRef = _groupRef.collection('reads').doc(myUid);
      batch.set(
        readRef,
        {
          'uid': myUid,
          'lastReadAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
      _patchPendingAudio(pendingId, sending: false);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('GroupAudio: erro ao enviar: $e\n$st');
      }
      _markPendingAudioFailed(pendingId);
      _notifySendFailed();
    } finally {
      _endPendingSend(pendingId);
    }
  }

  Future<void> _sendGroupImageMessage(
    String localPath, {
    String? retryMessageId,
  }) async {
    final myUid = uid;
    if (myUid == null || (!_canSend && retryMessageId == null)) return;

    final isRetry = retryMessageId != null;
    late final String pendingId;
    late final _PendingReplyData reply;
    String? cachedUploadUrl;
    var path = localPath;

    if (isRetry) {
      final i = _pendingImages.indexWhere((e) => e.localId == retryMessageId);
      if (i < 0) return;
      final item = _pendingImages[i];
      if (!ChatMessageListStability.canStartRetry(
        failed: item.failed,
        sending: item.sending || _inFlightPendingIds.contains(item.localId),
      )) {
        return;
      }
      pendingId = item.localId;
      path = item.localPath;
      reply = item.reply;
      cachedUploadUrl = item.uploadedUrl;
      if (!_beginPendingSend(pendingId)) return;
      _patchPendingImage(pendingId, failed: false, sending: true);
    } else {
      final mySnap =
          await FirebaseFirestore.instance.collection('users').doc(myUid).get();

      if (mySnap.data()?['shadowBan'] == true) {
        _toast(AppTexts.current.get('user_temporarily_silenced'));
        return;
      }

      pendingId = _msgsRef.doc().id;
      reply = _captureReplyData();
      if (!_beginPendingSend(pendingId)) return;
      if (mounted) {
        setState(() {
          _pendingImages.insert(
            0,
            _PendingImageItem(
              localId: pendingId,
              senderId: myUid,
              createdAt: DateTime.now(),
              localPath: path,
              reply: reply,
              sending: true,
            ),
          );
        });
      }
      _cancelReply();
    }

    try {
      var imageUrl = ChatMessageListStability.resolveUploadUrl(
        cachedUploadUrl: cachedUploadUrl,
      );

      if (imageUrl == null) {
        imageUrl = await _uploadGroupImageToStorage(
          groupId: widget.groupId,
          myUid: myUid,
          localPath: path,
        );
        _patchPendingImage(pendingId, uploadedUrl: imageUrl);
      } else if (kDebugMode) {
        debugPrint('GroupImage: reutilizando upload existente');
      }

      final batch = FirebaseFirestore.instance.batch();
      final msgRef = _msgsRef.doc(pendingId);

      batch.set(msgRef, {
        'type': 'image',
        'text': '',
        'imageUrl': imageUrl,
        'senderId': myUid,
        'createdAt': FieldValue.serverTimestamp(),
        'replyToMessageId': reply.replyToMessageId,
        'replyToText': reply.replyToText,
        'replyToType': reply.replyToType,
        'replyToIsMe': reply.replyToIsMe,
        'replyToImageUrl': reply.replyToImageUrl,
        'deleted': false,
        'deletedBy': '',
        'deletedText': '',
        'deletedAt': null,
      });

      final readRef = _groupRef.collection('reads').doc(myUid);
      batch.set(
        readRef,
        {
          'uid': myUid,
          'lastReadAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
      _patchPendingImage(pendingId, sending: false);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('GroupImage: erro ao enviar: $e\n$st');
      }
      _markPendingImageFailed(pendingId);
      _notifySendFailed();
    } finally {
      _endPendingSend(pendingId);
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (!_canSend) return;

    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );

      if (file == null) return;

      await _sendGroupImageMessage(file.path);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('GroupImage: erro ao escolher imagem: $e\n$st');
      }
      _notifySendFailed();
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
    final myUid = uid;
    if (myUid == null) return;

    try {
      await _msgsRef.doc(messageId).set({
        'deleted': true,
        'deletedBy': myUid,
        'deletedText': t.get('group_message_deleted_by_admin'),
        'deletedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
    required String senderId,
    required Map<String, dynamic> data,
  }) async {
    final t = AppTexts.current;
    if (_loadingRole) return;
    final canDelete = isMyMessage || _isAdmin;
    final forwardable = canForwardMessageData(data);

    if (!canDelete && !forwardable) return;

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
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(t.get('report_message')),
                onTap: () async {
                  Navigator.pop(context);
                  await _reportMessage(
                    messageId: messageId,
                    reportedUid: senderId,
                  );
                },
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(t.get('group_delete_for_me')),
                onTap: () async {
                  Navigator.pop(context);
                  await _deleteForMe(messageId: messageId);
                },
              ),
            if (canDelete)
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
          source: ForwardSource.group(
            groupId: widget.groupId,
            messageId: messageId,
          ),
          previewLabel: preview,
        ),
      ),
    );
  }

  Future<void> _sendGroupReport(String reason) async {
    final myUid = uid;
    if (myUid == null) return;

    try {
      await FirebaseFirestore.instance.collection('reports').add({
        'fromUid': myUid,
        'reportedUid': '',
        'reason': reason,
        'status': 'open',
        'contextType': 'group',
        'groupId': widget.groupId,
        'groupName': widget.groupName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.current.get('report_sent'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppTexts.current.get('error_prefix')} $e')),
      );
    }
  }

  void _openGroupReportSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.flag),
              title: Text(
                  '${AppTexts.current.get('report_group')} ${widget.groupName}'),
            ),
            ListTile(
              title: Text(AppTexts.current.get('report_reason_spam')),
              onTap: () {
                Navigator.pop(context);
                _sendGroupReport('Spam');
              },
            ),
            ListTile(
              title: Text(AppTexts.current.get('report_reason_inappropriate')),
              onTap: () {
                Navigator.pop(context);
                _sendGroupReport('Conteúdo impróprio');
              },
            ),
            ListTile(
              title: Text(AppTexts.current.get('report_reason_harassment')),
              onTap: () {
                Navigator.pop(context);
                _sendGroupReport('Assédio');
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

  Set<String> _groupMemberIds() {
    final raw = _groupData?['members'];
    if (raw is! List) return <String>{};
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  Set<String> _groupBannedIds() {
    final data = _groupData;
    if (data == null) return <String>{};
    final out = <String>{};
    for (final key in ['banned', 'bannedMembers', 'bannedUids']) {
      final raw = data[key];
      if (raw is List) {
        out.addAll(
          raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
        );
      }
    }
    final bannedMap = data['bannedMap'];
    if (bannedMap is Map) {
      for (final e in bannedMap.entries) {
        if (e.value == true) out.add(e.key.toString().trim());
      }
    }
    return out;
  }

  Stream<int> _groupOnlineCountStream() {
    final members = _groupMemberIds();
    final banned = _groupBannedIds();
    return PresenceWatch.watchOnlineCount(
      uids: members,
      excludeUids: banned,
      maxWatches: PresenceRtdbConfig.maxGroupPresenceWatches,
    );
  }

  GroupOnlineDisplay _groupOnlineDisplay(int watchedOnline) {
    final members = _groupMemberIds().difference(_groupBannedIds());
    final watched = PresenceRtdbLogic.capMemberWatches(
      members,
      prioritizeUid: uid,
      max: PresenceRtdbConfig.maxGroupPresenceWatches,
    );
    return PresenceRtdbLogic.groupOnlineDisplay(
      memberCount: members.length,
      watchedOnlineCount: watchedOnline,
      watchedMemberCount: watched.length,
    );
  }

  String _formatGroupOnlineLabel(GroupOnlineDisplay display) {
    final t = AppTexts.current;
    if (!display.isPartial) {
      return OnlineStatus.formatOnlineCount(
        count: display.count,
        onlineWord: t.get('online'),
      );
    }
    // Contagem parcial explícita — nunca como total exato.
    return t
        .get('online_count_partial')
        .replaceAll('{count}', '${display.count}');
  }

  String _presenceLabel(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
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

  Widget _buildPreviewMessagesPlaceholder() {
    final t = AppTexts.current;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          _isBanned
              ? t.get('group_cannot_join_banned')
              : t.get('group_preview_join_hint'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _muted,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ),
    );
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                      color: _replyToIsMe ? _remdyBlue : _muted,
                      width: 4,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: const BorderSide(color: _border),
                      ),
                      child: Text(
                        t.get('group_back'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _text,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_isBanned || _joining) ? null : _joinGroup,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _remdyBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        disabledBackgroundColor: const Color(0xFFE5E7EB),
                        disabledForegroundColor: _muted,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _joining
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isBanned
                                  ? t.get('group_you_are_banned')
                                  : t.get('group_join'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
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

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final headerName =
        ((_groupData?['name'] ?? widget.groupName).toString().trim()).isEmpty
            ? widget.groupName
            : (_groupData?['name'] ?? widget.groupName).toString().trim();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        iconTheme: const IconThemeData(color: _muted),
        centerTitle: true,
        actions: [
          if (!_searchMode)
            IconButton(
              onPressed: _openGroupReportSheet,
              icon: const Icon(Icons.flag_outlined, color: _muted),
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
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
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
                GroupJoinUiLogic.shouldListenToMemberStreams(
                  isMember: _isMember,
                  isBanned: _isBanned,
                )
                    ? StreamBuilder<int>(
                  stream: _groupOnlineCountStream(),
                  initialData: 0,
                  builder: (context, onlineSnap) {
                    final watchedOnline = onlineSnap.data ?? 0;
                    final display = _groupOnlineDisplay(watchedOnline);
                    final onlineCount = display.count;
                    final onlineLabel = _formatGroupOnlineLabel(display);

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _presenceRef.snapshots(),
                      builder: (context, snap) {
                        final docs = snap.data?.docs ?? [];
                        final typingLabel = _presenceLabel(docs);

                        if (onlineCount <= 0 && typingLabel.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (onlineCount > 0)
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      onlineLabel,
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              if (typingLabel.isNotEmpty) ...[
                                if (onlineCount > 0) const SizedBox(height: 2),
                                Text(
                                  typingLabel,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                )
                    : const SizedBox.shrink(),
                Expanded(
                  child: GroupJoinUiLogic.shouldListenToMemberStreams(
                    isMember: _isMember,
                    isBanned: _isBanned,
                  )
                      ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _msgsRef
                              .orderBy('createdAt', descending: true)
                              .snapshots(),
                          builder: (context, snap) {
                            // Erro (ex.: permission) NUNCA vira spinner eterno.
                            if (snap.hasError) {
                              debugPrint(
                                'GroupChat messages stream error: ${snap.error}',
                              );
                              if (_cachedMsgDocs.isEmpty) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          t.get('group_messages_load_error'),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: _muted,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextButton(
                                          onPressed: () {
                                            if (mounted) setState(() {});
                                          },
                                          child: Text(
                                            t.get('user_search_retry'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                            }

                            if (snap.hasData) {
                              _cachedMsgDocs = snap.data!.docs;
                            }

                            final showSpinner =
                                GroupJoinUiLogic.shouldShowMessagesSpinner(
                              isMember: _isMember,
                              hasData: snap.hasData,
                              hasError: snap.hasError,
                              waiting: snap.connectionState ==
                                  ConnectionState.waiting,
                              hasCachedDocs: _cachedMsgDocs.isNotEmpty,
                            );

                            if (showSpinner) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final allDocs = _cachedMsgDocs;

                            final docs = _searchText.isEmpty
                                ? allDocs
                                : allDocs.where((doc) {
                                    final data = doc.data();
                                    final text = (data['text'] ?? '')
                                        .toString()
                                        .toLowerCase();
                                    return text.contains(_searchText);
                                  }).toList();

                      final serverIds = allDocs.map((d) => d.id).toSet();
                      _syncPendingWithServerIds(serverIds);

                      final visiblePendingImages = _pendingImages
                          .where(
                            (e) => ChatMessageListStability.shouldShowPending(
                              pendingId: e.localId,
                              serverIds: serverIds,
                            ),
                          )
                          .toList();
                      final visiblePendingAudios = _pendingAudios
                          .where(
                            (e) => ChatMessageListStability.shouldShowPending(
                              pendingId: e.localId,
                              serverIds: serverIds,
                            ),
                          )
                          .toList();
                      final visiblePendingTexts = _pendingTexts
                          .where(
                            (e) => ChatMessageListStability.shouldShowPending(
                              pendingId: e.localId,
                              serverIds: serverIds,
                            ),
                          )
                          .toList();

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _preloadUsersFromDocs(docs);
                        _maybeAutoScroll(
                          docs.length +
                              visiblePendingAudios.length +
                              visiblePendingImages.length +
                              visiblePendingTexts.length,
                        );
                      });

                      final totalCount = docs.length +
                          visiblePendingAudios.length +
                          visiblePendingImages.length +
                          visiblePendingTexts.length;

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
                          if (i < visiblePendingImages.length) {
                            final pending = visiblePendingImages[i];
                            final isMe = pending.senderId == uid;

                            return KeyedSubtree(
                              key: ValueKey(
                                ChatMessageListStability.bubbleKey(
                                  pending.localId,
                                ),
                              ),
                              child: _ImageSendingBubble(
                                isMe: isMe,
                                timeText:
                                    _formatTimeFromDate(pending.createdAt),
                                localPath: pending.localPath,
                                failed: pending.failed,
                                onRetry: pending.failed && !pending.sending
                                    ? () => _retryPendingImage(pending.localId)
                                    : null,
                              ),
                            );
                          }

                          final afterPendingImages =
                              i - visiblePendingImages.length;

                          if (afterPendingImages <
                              visiblePendingAudios.length) {
                            final pending =
                                visiblePendingAudios[afterPendingImages];
                            final isMe = pending.senderId == uid;

                            return KeyedSubtree(
                              key: ValueKey(
                                ChatMessageListStability.bubbleKey(
                                  pending.localId,
                                ),
                              ),
                              child: _AudioSendingBubble(
                                isMe: isMe,
                                timeText:
                                    _formatTimeFromDate(pending.createdAt),
                                failed: pending.failed,
                                onRetry: pending.failed && !pending.sending
                                    ? () => _retryPendingAudio(pending.localId)
                                    : null,
                              ),
                            );
                          }

                          final afterPendingMedia =
                              afterPendingImages - visiblePendingAudios.length;

                          if (afterPendingMedia < visiblePendingTexts.length) {
                            final pending =
                                visiblePendingTexts[afterPendingMedia];
                            final isMe = pending.senderId == uid;

                            return KeyedSubtree(
                              key: ValueKey(
                                ChatMessageListStability.bubbleKey(
                                  pending.localId,
                                ),
                              ),
                              child: _TextSendingBubble(
                                isMe: isMe,
                                text: pending.text,
                                timeText:
                                    _formatTimeFromDate(pending.createdAt),
                                failed: pending.failed,
                                onRetry: pending.failed && !pending.sending
                                    ? () => _retryPendingText(pending.localId)
                                    : null,
                              ),
                            );
                          }

                          final realIndex =
                              afterPendingMedia - visiblePendingTexts.length;
                          final doc = docs[realIndex];
                          final d = doc.data();
                          final bubbleKey = ValueKey(
                            ChatMessageListStability.bubbleKey(doc.id),
                          );

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
                          final clientCreatedAt =
                              d['clientCreatedAt'] as Timestamp?;
                          final timeTs = createdAt ?? clientCreatedAt;

                          Widget bubbleWidget;

                          final replyToText =
                              (d['replyToText'] ?? '').toString();
                          final replyToType =
                              (d['replyToType'] ?? 'text').toString();
                          final replyToIsMe = d['replyToIsMe'] == true;
                          final replyToImageUrl =
                              (d['replyToImageUrl'] ?? '').toString();

                          if (deleted) {
                            final text = deletedText.isNotEmpty
                                ? deletedText
                                : t.get('group_message_deleted_by_admin');

                            bubbleWidget = _Bubble(
                              text: text,
                              isMe: isMe,
                              isDeleted: true,
                              timeText: _formatTime(timeTs),
                              replyToText: replyToText,
                              replyToType: replyToType,
                              replyToIsMe: replyToIsMe,
                              replyToImageUrl: replyToImageUrl,
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
                                timeText: _formatTime(timeTs),
                              );
                            } else {
                              bubbleWidget = AudioBubble(
                                key: ValueKey(doc.id),
                                messageId: doc.id,
                                audioUrl: url,
                                isMe: isMe,
                                durationMs: durationMs,
                                timeText: _formatTime(timeTs),
                                forwarded: d['forwarded'] == true,
                              );
                            }
                          } else if (type == 'image') {
                            final imageUrl = (d['imageUrl'] ?? '').toString();

                            bubbleWidget = _ImageBubble(
                              imageUrl: imageUrl,
                              isMe: isMe,
                              timeText: _formatTime(timeTs),
                              forwarded: d['forwarded'] == true,
                            );
                          } else {
                            final text = (d['text'] ?? '').toString();
                            bubbleWidget = _Bubble(
                              text: text,
                              isMe: isMe,
                              isDeleted: false,
                              timeText: _formatTime(timeTs),
                              replyToText: replyToText,
                              replyToType: replyToType,
                              replyToIsMe: replyToIsMe,
                              replyToImageUrl: replyToImageUrl,
                              forwarded: d['forwarded'] == true,
                              linkPreview:
                                  LinkPreviewData.fromMap(d['linkPreview']),
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

                          return Column(
                            key: bubbleKey,
                            children: [
                              if (_shouldShowDateHeader(docs, realIndex))
                                _DateHeader(
                                  label: _formatDayLabel(timeTs),
                                ),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  if (!_searchMode) return;

                                  final msg = {
                                    ...d,
                                    'id': doc.id,
                                  };

                                  _handleReplyFromMessage(msg, type);

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
                                    final msg = {
                                      ...d,
                                      'id': doc.id,
                                    };
                                    _handleReplyFromMessage(msg, type);
                                  }
                                  _dragDx = 0;
                                },
                                onHorizontalDragCancel: () {
                                  _dragDx = 0;
                                },
                                onLongPress: () async {
                                  if (_searchMode) return;

                                  await _openActions(
                                    messageId: doc.id,
                                    isMyMessage: isMe,
                                    senderId: senderId,
                                    data: Map<String, dynamic>.from(d),
                                  );
                                },
                                child: bubble,
                              ),
                            ],
                          );
                        },
                      );
                    },
                  )
                      : _buildPreviewMessagesPlaceholder(),
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
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
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
                                            if (_replyToType == 'image' &&
                                                _replyToImageUrl.isNotEmpty)
                                              Row(
                                                children: [
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
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
                                                            Alignment.center,
                                                        child: const Icon(
                                                            Icons.image,
                                                            size: 18),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      t.get('chat_photo_label'),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
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
                                                        ? t.get(
                                                            'chat_photo_label')
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
                                        color: Colors.grey.shade100,
                                        borderRadius:
                                            BorderRadius.circular(999),
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
                                                  ? (_isWorldGroup &&
                                                          !_isPremium
                                                      ? 'Grupo de outro país é Premium'
                                                      : t.get(
                                                          'group_cannot_send_in_this_group'))
                                                  : t.get('group_type_message'),
                                          border: InputBorder.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: (uid == null || !_canSend)
                                        ? null
                                        : _openPlusMenu,
                                    borderRadius: BorderRadius.circular(999),
                                    child: Opacity(
                                      opacity:
                                          (uid == null || !_canSend) ? 0.5 : 1,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius:
                                              BorderRadius.circular(999),
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
                                      ? Opacity(
                                          opacity: (uid == null || !_canSend)
                                              ? 0.5
                                              : 1,
                                          child: IgnorePointer(
                                            ignoring: uid == null || !_canSend,
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

                                                await _sendGroupAudioMessage(
                                                    path);
                                              },
                                            ),
                                          ),
                                        )
                                      : InkWell(
                                          onTap: _send,
                                          borderRadius:
                                              BorderRadius.circular(999),
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
                            ],
                          ),
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
  final String localId;
  final String senderId;
  final DateTime createdAt;
  final String? localPath;
  final bool failed;
  final bool sending;
  final String? uploadedUrl;
  final int? durationMs;
  final _PendingReplyData reply;

  _PendingAudioItem({
    required this.localId,
    required this.senderId,
    required this.createdAt,
    required this.reply,
    this.localPath,
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
      localId: localId,
      senderId: senderId,
      createdAt: createdAt,
      localPath: localPath,
      reply: reply,
      failed: failed ?? this.failed,
      sending: sending ?? this.sending,
      uploadedUrl: uploadedUrl ?? this.uploadedUrl,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}

class _PendingImageItem {
  final String localId;
  final String senderId;
  final DateTime createdAt;
  final String localPath;
  final bool failed;
  final bool sending;
  final String? uploadedUrl;
  final _PendingReplyData reply;

  _PendingImageItem({
    required this.localId,
    required this.senderId,
    required this.createdAt,
    required this.localPath,
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
      localId: localId,
      senderId: senderId,
      createdAt: createdAt,
      localPath: localPath,
      reply: reply,
      failed: failed ?? this.failed,
      sending: sending ?? this.sending,
      uploadedUrl: uploadedUrl ?? this.uploadedUrl,
    );
  }
}

class _PendingTextItem {
  final String localId;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final bool failed;
  final bool sending;
  final _PendingReplyData reply;

  _PendingTextItem({
    required this.localId,
    required this.senderId,
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
      localId: localId,
      senderId: senderId,
      text: text,
      createdAt: createdAt,
      reply: reply,
      failed: failed ?? this.failed,
      sending: sending ?? this.sending,
    );
  }
}

class _TextSendingBubble extends StatelessWidget {
  final bool isMe;
  final String text;
  final String timeText;
  final bool failed;
  final VoidCallback? onRetry;

  const _TextSendingBubble({
    required this.isMe,
    required this.text,
    required this.timeText,
    this.failed = false,
    this.onRetry,
  });

  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final bg = isMe ? _remdyBlue : Colors.white;
    final fg = isMe ? Colors.white : const Color(0xFF111827);

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
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(text, style: TextStyle(color: fg, fontSize: 15)),
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
                      color: isMe ? Colors.white : _remdyBlue,
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
                      fontWeight: FontWeight.w700,
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
  final String timeText;
  final bool failed;
  final VoidCallback? onRetry;

  const _AudioSendingBubble({
    required this.isMe,
    required this.timeText,
    this.failed = false,
    this.onRetry,
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
            if (!failed)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isMe ? Colors.white : _remdyBlue,
                ),
              )
            else
              Icon(
                Icons.error_outline,
                size: 18,
                color: isMe ? Colors.white : Colors.redAccent,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    failed
                        ? t.get('chat_send_failed')
                        : t.get('group_sending_audio'),
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  if (failed && onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        foregroundColor: fg,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(t.get('chat_retry_send')),
                    )
                  else ...[
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
  final bool failed;
  final VoidCallback? onRetry;

  const _ImageSendingBubble({
    required this.isMe,
    required this.timeText,
    required this.localPath,
    this.failed = false,
    this.onRetry,
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
                if (!failed)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isMe ? Colors.white : _remdyBlue,
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
                        : t.get('group_sending_image'),
                    style: TextStyle(
                      color: isMe ? Colors.white : const Color(0xFF111827),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
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
  final String replyToText;
  final String replyToType;
  final bool replyToIsMe;
  final String replyToImageUrl;
  final LinkPreviewData? linkPreview;
  final bool forwarded;

  const _Bubble({
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

  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
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
            if (replyToText.isNotEmpty) ...[
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
                      replyToIsMe
                          ? AppTexts.current.get('chat_you')
                          : AppTexts.current.get('chat_reply'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isMe ? Colors.white70 : const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      replyToType == 'audio'
                          ? AppTexts.current.get('chat_audio_label')
                          : replyToType == 'image'
                              ? AppTexts.current.get('chat_photo_label')
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
            ],
            MessageTextWithLinks(
              text: text,
              enabled: !isDeleted,
              style: style,
              linkStyle: style.copyWith(
                decoration: TextDecoration.underline,
                color: isMe ? Colors.white : const Color(0xFF1D4ED8),
              ),
            ),
            if (!isDeleted && linkPreview != null)
              LinkPreviewCard(data: linkPreview!, isMe: isMe),
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
