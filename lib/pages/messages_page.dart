import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


import 'chat_page.dart';
import '../l10n/app_texts.dart';


class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});


  @override
  State<MessagesPage> createState() => _MessagesPageState();
}


class _MessagesPageState extends State<MessagesPage> {
  String get _myUid => FirebaseAuth.instance.currentUser!.uid;


  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);


  String _loadedLocaleCode = '';


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


  Future<void> _hideConversationForMe(String conversationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .set({
        'hiddenFor': FieldValue.arrayUnion([_myUid]),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Erro ao esconder conversa: $e');
    }
  }


  void _openConversationActions(String conversationId) {
    final t = AppTexts.current;


    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: Text(
                    t.get('delete_for_me'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _text,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _hideConversationForMe(conversationId);
                  },
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final db = FirebaseFirestore.instance;


    final convQuery = db
        .collection('conversations')
        .where('participants', arrayContains: _myUid)
        .orderBy('lastMessageAt', descending: true);


    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        centerTitle: false,
        title: Text(
          t.get('messages'),
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: _muted),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: convQuery.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('${t.get('error')}: ${snap.error}'));
          }


          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Text(
                t.get('no_conversations_yet'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _muted,
                ),
              ),
            );
          }


          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final convDoc = docs[i];
              final data = convDoc.data();


              final hiddenRaw = data['hiddenFor'];
              final hiddenFor = (hiddenRaw is List)
                  ? hiddenRaw.map((e) => e.toString()).toList()
                  : <String>[];


              if (hiddenFor.contains(_myUid)) {
                return const SizedBox.shrink();
              }


              final participants =
                  (data['participants'] as List?)?.cast<String>() ?? [];


              final otherUid = participants.firstWhere(
                (u) => u != _myUid,
                orElse: () => '',
              );


              final lastMessage = (data['lastMessage'] ?? '').toString();


              final unreadMap = (data['unread'] is Map)
                  ? Map<String, dynamic>.from(data['unread'])
                  : <String, dynamic>{};


              final myUnread =
                  (unreadMap[_myUid] is int) ? unreadMap[_myUid] as int : 0;


              final myUnread2 = (myUnread == 0 && data['unreadCount'] is Map)
                  ? ((data['unreadCount'][_myUid] is int)
                      ? data['unreadCount'][_myUid] as int
                      : 0)
                  : 0;


              final unreadFinal = myUnread > 0 ? myUnread : myUnread2;


              if (otherUid.isEmpty) {
                return _ConversationTile(
                  uid: '',
                  name: t.get('user'),
                  photoUrl: '',
                  subtitle: lastMessage,
                  unread: unreadFinal,
                  onLongPress: () => _openConversationActions(convDoc.id),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatPage(
                          conversationId: convDoc.id,
                          otherUid: otherUid,
                          otherName: t.get('user'),
                        ),
                      ),
                    );
                  },
                );
              }


              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: db.collection('users').doc(otherUid).snapshots(),
                builder: (context, userSnap) {
                  final u = userSnap.data?.data() ?? {};
                  final name = (u['name'] ?? t.get('user')).toString();
                  final photoUrl = (u['photoUrl'] ?? '').toString();


                  return _ConversationTile(
                    uid: otherUid,
                    name: name,
                    photoUrl: photoUrl,
                    subtitle: lastMessage,
                    unread: unreadFinal,
                    onLongPress: () => _openConversationActions(convDoc.id),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatPage(
                            conversationId: convDoc.id,
                            otherUid: otherUid,
                            otherName: name,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}


class _ConversationTile extends StatelessWidget {
  final String uid;
  final String name;
  final String photoUrl;
  final String subtitle;
  final int unread;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;


  const _ConversationTile({
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.subtitle,
    required this.unread,
    required this.onTap,
    this.onLongPress,
  });


  static const Color _card = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final hasUnread = unread > 0;


    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            _AvatarOnline(
              uid: uid,
              photoUrl: photoUrl,
              size: 52,
              onlineSeconds: 90,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: hasUnread ? FontWeight.w900 : FontWeight.w800,
                      fontSize: 15.5,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle.isNotEmpty ? subtitle : t.get('tap_to_open'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasUnread ? _text : _muted,
                      fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 13.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _remdyBlue,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 24),
                const SizedBox(height: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: Color(0xFFCBD5E1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class _AvatarOnline extends StatelessWidget {
  final String uid;
  final String photoUrl;
  final double size;
  final int onlineSeconds;


  const _AvatarOnline({
    required this.uid,
    required this.photoUrl,
    required this.size,
    required this.onlineSeconds,
  });


  DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is int) {
      if (v < 2000000000) {
        return DateTime.fromMillisecondsSinceEpoch(v * 1000);
      }
      return DateTime.fromMillisecondsSinceEpoch(v);
    }
    if (v is num) {
      final n = v.toInt();
      if (n < 2000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n * 1000);
      }
      return DateTime.fromMillisecondsSinceEpoch(n);
    }
    if (v is String) return DateTime.tryParse(v);
    return null;
  }


  bool _isOnlineFrom(Map<String, dynamic> data) {
    final now = DateTime.now();
    final lastSeen = _toDateTime(data['lastSeenAt']);
    final updated = _toDateTime(data['updatedAt']);


    bool recent(DateTime? dt) {
      if (dt == null) return false;
      final diff = now.difference(dt).inSeconds;
      return diff <= onlineSeconds;
    }


    return recent(lastSeen) || recent(updated);
  }


  @override
  Widget build(BuildContext context) {
    final hasUid = uid.trim().isNotEmpty;


    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF1F5F9),
        image: photoUrl.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(photoUrl),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: photoUrl.isEmpty
          ? const Icon(Icons.person, color: Color(0xFF6B7280))
          : null,
    );


    if (!hasUid) {
      return Stack(clipBehavior: Clip.none, children: [avatar]);
    }


    final db = FirebaseFirestore.instance;
    final pubStream = db.collection('publicUsers').doc(uid).snapshots();


    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: pubStream,
      builder: (context, snap) {
        Map<String, dynamic> data = {};
        if (snap.hasData && (snap.data?.exists ?? false)) {
          data = snap.data?.data() ?? {};
        }


        if (data.isEmpty) {
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: db.collection('users').doc(uid).snapshots(),
            builder: (context, s2) {
              final Map<String, dynamic> d2 =
                  (s2.hasData && (s2.data?.exists ?? false))
                      ? (s2.data?.data() ?? <String, dynamic>{})
                      : <String, dynamic>{};


              final isOnline = _isOnlineFrom(d2);


              return Stack(
                clipBehavior: Clip.none,
                children: [
                  avatar,
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFCBD5E1),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        }


        final isOnline = _isOnlineFrom(data);


        return Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isOnline
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFCBD5E1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
