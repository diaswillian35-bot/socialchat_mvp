import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';


import 'home_page.dart';
import 'messages_page.dart';
import 'groups_list_page.dart';
import 'events_page.dart';
import 'create_group_page.dart';


import '../services/presence_service.dart';
import '../services/push_service.dart';


class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});
  final int initialIndex;


  @override
  State<MainShell> createState() => _MainShellState();
}


class _MainShellState extends State<MainShell> {
  late int _index;


  static const Color _remdyBlue = Color(0xFF313A5F);


  @override
  void initState() {
    super.initState();


    _index = widget.initialIndex;
    if (_index < 0 || _index > 3) _index = 0;


    WidgetsBinding.instance.addPostFrameCallback((_) async {
      PresenceService.instance.start();
      
    });
  }


  // ==========================
  // 🔴 UNREAD MENSAGENS
  // ==========================
  Stream<int> _unreadMessagesStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(0);


    return FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snap) {
      int total = 0;


      for (final d in snap.docs) {
        final data = d.data();
        final unread = (data['unread'] ?? {})[uid] ?? 0;
        if (unread is num && unread > 0) total++;
      }


      return total;
    });
  }


  // ==========================
  // 🔴 UNREAD GRUPOS
  // ==========================
  Stream<int> _unreadGroupsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(0);


    return FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: uid)
        .snapshots()
        .map((snap) {
      int total = 0;


      for (final d in snap.docs) {
        final data = d.data();
        final unread = (data['unread'] ?? {})[uid] ?? 0;
        if (unread is num && unread > 0) total++;
      }


      return total;
    });
  }


  @override
  Widget build(BuildContext context) {
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


      // FAB só na aba grupos
      floatingActionButton: _index == 2
          ? FloatingActionButton(
              backgroundColor: _remdyBlue,
              foregroundColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CreateGroupPage()),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,


      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFFF1F5F9),
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: _remdyBlue,
        unselectedItemColor: const Color(0xFF9CA3AF),
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600),


        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),


          // 🔴 MENSAGENS
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
            label: 'Mensagens',
          ),


          // 🔴 GRUPOS
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
            label: 'Grupos',
          ),


          const BottomNavigationBarItem(
            icon: Icon(Icons.event_rounded),
            label: 'Eventos',
          ),
        ],
      ),
    );
  }
}


// ==========================
// 🔴 Badge widget reutilizável
// ==========================
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
