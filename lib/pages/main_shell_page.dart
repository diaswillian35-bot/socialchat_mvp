import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

import 'home_page.dart';
import 'messages_page.dart';
import 'groups_list_page.dart';
import 'events_page_new.dart';
import 'create_group_page.dart';


import '../services/presence_service.dart';
import '../services/push_service.dart';
import '../l10n/app_texts.dart';


class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});
  final int initialIndex;


  @override
  State<MainShell> createState() => _MainShellState();
}


class _MainShellState extends State<MainShell> {
  late int _index;


  static const Color _remdyBlue = Color(0xFF313A5F);


  String _loadedLocaleCode = '';

Future<void> _checkBannedUser() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get();

  if (snap.data()?['isBanned'] == true) {
    await FirebaseAuth.instance.signOut();
  }
}



  
@override
void initState() {
  super.initState();

  _index = widget.initialIndex;
  if (_index < 0 || _index > 3) _index = 0;

  _checkBannedUser();

  WidgetsBinding.instance.addPostFrameCallback((_) async {


      await PresenceService.instance.start();


      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await PushService.init();
        await PushService.start(uid);
      }
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
    PresenceService.instance.stop();
    super.dispose();
  }


  int _readUnreadFromMap(Map<String, dynamic> data, String uid) {
    final unreadRaw = data['unread'];


    if (unreadRaw is Map<String, dynamic>) {
      final value = unreadRaw[uid];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }


    if (unreadRaw is Map) {
      final value = unreadRaw[uid];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }


    return 0;
  }


  Stream<int> _unreadMessagesStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(0);


    return FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snap) {
      int total = 0;


      for (final doc in snap.docs) {
        final data = doc.data();
        final unread = _readUnreadFromMap(data, uid);
        if (unread > 0) total++;
      }


      return total;
    });
  }


  Stream<int> _unreadGroupsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(0);


    return FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: uid)
        .where('deleted', isEqualTo: false)
        .snapshots()
        .map((snap) {
      int total = 0;


      for (final doc in snap.docs) {
        final data = doc.data();
        final unread = _readUnreadFromMap(data, uid);
        if (unread > 0) total++;
      }


      return total;
    });
  }

Stream<int> _activeEventsStream() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(0);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snap) {
    final data = snap.data() ?? {};
    return data['hasNewEvents'] == true ? 1 : 0;
  });
}





  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;


    final pages = <Widget>[
      const HomePage(),
      const MessagesPage(),
      const GroupsListPage(),
      const EventsPage(),
    ];


    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      floatingActionButton: _index == 2
         ? FloatingActionButton(
    heroTag: null,

              backgroundColor: _remdyBlue,
              foregroundColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateGroupPage(),
                  ),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFFF1F5F9),
        currentIndex: _index,
        onTap: (i) async {
  setState(() => _index = i);

  if (i == 3) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
        'lastEventsSeenAt': FieldValue.serverTimestamp(),
        'hasNewEvents': false,
      }, SetOptions(merge: true));
    }
  }
},


        type: BottomNavigationBarType.fixed,
        selectedItemColor: _remdyBlue,
        unselectedItemColor: const Color(0xFF9CA3AF),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_rounded),
            label: t.get('home'),
          ),
          BottomNavigationBarItem(
            icon: StreamBuilder<int>(
              stream: _unreadMessagesStream(),
              builder: (context, snap) {
                final n = snap.data ?? 0;


                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.chat_bubble_rounded),
                    if (n > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: _Badge(count: n),
                      ),
                  ],
                );
              },
            ),
            label: t.get('messages'),
          ),
          BottomNavigationBarItem(
            icon: StreamBuilder<int>(
              stream: _unreadGroupsStream(),
              builder: (context, snap) {
                final n = snap.data ?? 0;


                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.groups_rounded),
                    if (n > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: _Badge(count: n),
                      ),
                  ],
                );
              },
            ),
            label: t.get('groups'),
          ),
BottomNavigationBarItem(
  icon: StreamBuilder<int>(
    stream: _activeEventsStream(),
    builder: (context, snap) {
      final n = snap.data ?? 0;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.event_rounded),

          if (n > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      );
    },
  ),
  label: t.get('events'),
),




        ],
      ),
    );
  }
}


class _Badge extends StatelessWidget {
  final int count;


  const _Badge({required this.count});


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      decoration: const BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
