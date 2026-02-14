import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:socialchat_mvp/pages/public_profile_page.dart';
import 'package:socialchat_mvp/services/block_service.dart';
import 'package:socialchat_mvp/pages/Premium_page.dart';

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

  final db = FirebaseFirestore.instance;
  final myUid = FirebaseAuth.instance.currentUser!.uid;

  bool _sending = false;
  DateTime? _lastSentAt;
  static const int _cooldownMs = 900;

  // anti-flicker
  int _lastMsgCount = 0;

  // ===== Premium =====
  bool _isPremium = false; // premium ativo (pago OU trial válido)
  bool _isPremiumPaid = false; // premium pago (sem limite)
  bool _isPremiumTrial = false; // trial válido (com limite mundo)
  DateTime? _premiumUntil;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _premiumSub;

  // ===== Escopo (país vs mundo) =====
  bool _isWorldChat = false;
  String _myCountryCode = '';
  String _otherCountryCode = '';

  // ===== Tempo trial (MUNDO) =====
  Timer? _usageTimer;
  int _dailySecondsUsed = 0;
  int _dailyLimitSeconds = 3600; // default 1h
  bool _limitReached = false;
  DateTime? _lastUsageWriteAt;

  // atualiza só o texto do timer
  final ValueNotifier<int> _remainingVN = ValueNotifier<int>(0);

  DocumentReference<Map<String, dynamic>> get convDoc =>
      db.collection('conversations').doc(widget.conversationId);

  CollectionReference<Map<String, dynamic>> get msgsCol =>
      convDoc.collection('messages');

  DocumentReference<Map<String, dynamic>> get myUserDoc =>
      db.collection('users').doc(myUid);

  DocumentReference<Map<String, dynamic>> get otherUserDoc =>
      db.collection('users').doc(widget.otherUid);

  // ✅ FIX: streams FIXOS (não recriar no build)
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _msgsStream;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _otherUserStream;
  late final Stream<bool> _blockedStream;

  // =======================
  // Remdy UI (só visual)
  // =======================
  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _card = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F); // azul Remdy
  static const Color _logoBlue = Color(0xFF264E9A); // azul logo

  String _formatSeconds(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  int get _remainingSeconds =>
      (_dailyLimitSeconds - _dailySecondsUsed).clamp(0, _dailyLimitSeconds);

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

  // NÃO MOSTRAR ALERTA/PUSH EM FOREGROUND
  Future<void> _disableForegroundPushUI() async {
    try {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
    } catch (_) {}
  }

  // ===== Premium listener =====
  void _listenPremium() {
    _premiumSub?.cancel();

    _premiumSub = myUserDoc.snapshots().listen((snap) {
      final data = snap.data() ?? {};

      final paid = (data['isPremium'] ?? false) == true;

      final type = (data['premiumType'] ?? '').toString(); // "trial"
      final untilRaw = data['premiumUntil'];
      DateTime? until;
      if (untilRaw is Timestamp) until = untilRaw.toDate();

      final trialActive =
          (type == 'trial') && (until != null) && until.isAfter(DateTime.now());

      _isPremiumPaid = paid;
      _isPremiumTrial = trialActive;
      _premiumUntil = until;

      final active = _isPremiumPaid || _isPremiumTrial;

      if (!mounted) return;
      setState(() {
        _isPremium = active;
      });

      _applyTimerRules(); // aplica regra final
    });
  }

  // ===== Descobre se é chat de mundo =====
  Future<void> _loadChatScope() async {
    try {
      final mySnap = await myUserDoc.get();
      final otherSnap = await otherUserDoc.get();

      final myData = mySnap.data() ?? {};
      final otherData = otherSnap.data() ?? {};

      _myCountryCode = (myData['countryCode'] ?? '').toString().toLowerCase();
      _otherCountryCode = (otherData['countryCode'] ?? '').toString().toLowerCase();

      _isWorldChat = _myCountryCode.isNotEmpty &&
          _otherCountryCode.isNotEmpty &&
          _myCountryCode != _otherCountryCode;

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      debugPrint('Erro _loadChatScope: $e');
    }
  }

  // ===== Regra final do timer =====
  void _applyTimerRules() {
    // ✅ Dentro do país: SEM tempo, sempre livre
    if (!_isWorldChat) {
      _limitReached = false;
      _usageTimer?.cancel();
      _usageTimer = null;
      _remainingVN.value = 0;
      if (mounted) setState(() {});
      return;
    }

    // ✅ Mundo:
    // Premium pago: sem limite
    if (_isPremiumPaid) {
      _limitReached = false;
      _usageTimer?.cancel();
      _usageTimer = null;
      _remainingVN.value = 0;
      if (mounted) setState(() {});
      return;
    }

    // Trial ativo: aplica limite (1h/dia)
    if (_isPremiumTrial) {
      _loadWorldDailyLimitAndStartTimer();
      return;
    }

    // Não premium: trava (segurança extra)
    _limitReached = true;
    _usageTimer?.cancel();
    _usageTimer = null;
    if (mounted) setState(() {});
  }

  Future<void> _loadWorldDailyLimitAndStartTimer() async {
    try {
      // só conta se for mundo e trial
      if (!_isWorldChat || !_isPremiumTrial) return;

      final snap = await myUserDoc.get();
      final data = snap.data() ?? {};

      final used = (data['dailySecondsUsedWorld'] is int)
          ? data['dailySecondsUsedWorld'] as int
          : 0;

      final rawLimit = (data['worldDailyLimitSeconds'] is int)
          ? data['worldDailyLimitSeconds'] as int
          : 3600;

      final limit = rawLimit < 60 ? 3600 : rawLimit;

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

    // só roda no mundo + trial + ainda não travou
    if (!_isWorldChat || !_isPremiumTrial || _limitReached) return;

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

  // ===== Read / unread =====
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

  // ===== Send =====
  Future<void> _send() async {
    // 🔒 Mundo: se atingiu limite (trial) OU não é premium, manda Premium
    if (_isWorldChat) {
      if (!_isPremium) {
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumPage()));
        return;
      }
      if (_limitReached && !_isPremiumPaid) {
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumPage()));
        return;
      }
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
      _warn('Links não são permitidos no chat.');
      return;
    }

    if (_containsPhone(text)) {
      _warn('Por segurança, não é permitido enviar número de telefone.');
      return;
    }

    _sending = true;
    _lastSentAt = now;
    _textC.clear();

    try {
      final msgData = <String, dynamic>{
        'text': text,
        'senderId': myUid,
        'fromUid': myUid,
        'toUid': widget.otherUid,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await msgsCol.add(msgData);

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

      // ✅ com reverse:true, o “fundo” é offset 0
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

  @override
  void initState() {
    super.initState();

    _disableForegroundPushUI();

    // ✅ FIX: streams FIXOS (não recriar no build)
    _msgsStream = msgsCol.orderBy('createdAt', descending: true).snapshots();
    _otherUserStream = otherUserDoc.snapshots();
    _blockedStream = BlockService.isEitherBlockedStream(widget.otherUid);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markAsRead();
    });

    // 1) descobre país vs mundo
    _loadChatScope().then((_) {
      // 2) premium listener
      _listenPremium();
      // 3) aplica regras de timer
      _applyTimerRules();
    });
  }

  @override
  void dispose() {
    _premiumSub?.cancel();
    _premiumSub = null;

    _usageTimer?.cancel();
    _usageTimer = null;

    _remainingVN.dispose();
    _textC.dispose();
    _scrollC.dispose();
    super.dispose();
  }

  void _openPublicProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PublicProfilePage(userUid: widget.otherUid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        titleSpacing: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Row(
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
                  backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
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
                  child: avatar,
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
                child: const Text(
                  'Premium',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: _text,
                  ),
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<bool>(
              stream: _blockedStream,
              initialData: false,
              builder: (context, blockSnap) {
                final isBlocked = blockSnap.data ?? false;

                // ✅ trava somente se: mundo + trial estourou OU mundo sem premium
                final lockByLimit = _isWorldChat && (!_isPremiumPaid) && _limitReached;
                final lockByNoPremium = _isWorldChat && !_isPremium;

                final locked = isBlocked || lockByLimit || lockByNoPremium;

                return Column(
                  children: [
                    Expanded(
                      child: isBlocked
                          ? const Center(child: Text('Chat indisponível (bloqueado).'))
                          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: _msgsStream,
                              builder: (context, snap) {
                                if (!snap.hasData) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                if (snap.hasError) {
                                  return Center(child: Text('Erro: ${snap.error}'));
                                }

                                final docs = snap.data?.docs ?? [];
                                if (docs.isEmpty) {
                                  return const Center(child: Text('Nenhuma mensagem ainda.'));
                                }

                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (!_scrollC.hasClients) return;
                                  if (docs.length != _lastMsgCount) {
                                    _lastMsgCount = docs.length;
                                    _scrollC.jumpTo(0);
                                  }
                                });

                                return ListView.builder(
                                  controller: _scrollC,
                                  reverse: true,
                                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                                  itemCount: docs.length,
                                  itemBuilder: (context, i) {
                                    final d = docs[i].data();
                                    final text = (d['text'] ?? '').toString();
                                    final senderId = (d['senderId'] ?? '').toString();
                                    final isMe = senderId == myUid;

                                    return _Bubble(
                                      text: text,
                                      isMe: isMe,
                                    );
                                  },
                                );
                              },
                            ),
                    ),

                    // ✅ contador aparece SÓ se: mundo + trial ativo
                    if (_isWorldChat && _isPremiumTrial && !_isPremiumPaid)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: ValueListenableBuilder<int>(
                          valueListenable: _remainingVN,
                          builder: (_, remaining, __) {
                            return Text(
                              _limitReached
                                  ? 'Tempo do Mundo acabou hoje.'
                                  : 'Tempo do Mundo hoje: ${_formatSeconds(remaining)}',
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
                        child: Row(
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
                                  enabled: !locked,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => locked ? null : _send(),
                                  decoration: InputDecoration(
                                    hintText: isBlocked
                                        ? 'Você não pode enviar mensagens (bloqueado).'
                                        : lockByNoPremium
                                            ? 'Mundo é Premium.'
                                            : lockByLimit
                                                ? 'Tempo do Mundo acabou. Vire Premium.'
                                                : 'Digite uma mensagem...',
                                    hintStyle: const TextStyle(
                                      color: _muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            InkWell(
                              onTap: locked ? null : _send,
                              borderRadius: BorderRadius.circular(999),
                              child: Opacity(
                                opacity: locked ? 0.4 : 1.0,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [_remdyBlue, _logoBlue],
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Icon(Icons.send_rounded, color: Colors.white),
                                ),
                              ),
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

class _Bubble extends StatelessWidget {
  final String text;
  final bool isMe;

  const _Bubble({
    super.key,
    required this.text,
    required this.isMe,
  });

  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    final bg = isMe ? _remdyBlue : Colors.white;
    final fg = isMe ? Colors.white : _text;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        child: Text(
          text,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}
