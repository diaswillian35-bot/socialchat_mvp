import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'home_page.dart';
import 'messages_page.dart';
import 'groups_page.dart';
import 'events_page.dart';
import 'create_group_page.dart'; // ✅ NOVO (ajuste o caminho se estiver em outra pasta)

import '../services/presence_service.dart'; // ✅

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _index;

  Stream<int> _unreadBubbleStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(0);

    return FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snap) {
      int totalChatsComNaoLidas = 0;

      for (final d in snap.docs) {
        final data = d.data() as Map<String, dynamic>;
        int unread = 0;

        final u = data['unread'];
        if (u is Map) {
          final v = u[uid];
          if (v is int) unread = v;
        }

        if (unread == 0) {
          final u2 = data['unreadCount'];
          if (u2 is Map) {
            final v2 = u2[uid];
            if (v2 is int) unread = v2;
          }
        }

        if (unread > 0) totalChatsComNaoLidas++;
      }

      return totalChatsComNaoLidas;
    });
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    if (_index < 0 || _index > 3) _index = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      PresenceService.instance.start();
    });
  }

  @override
  void dispose() {
    // ✅ quando sai do Shell (logout/fechar), marca offline corretamente
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const HomePage(),
      const MessagesPage(),
      const GroupsPage(),
      const EventsPage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: pages,
      ),

      // ✅ BOTÃO + só na aba "Grupos"
      floatingActionButton: _index == 2
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateGroupPage()),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,

      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFFF1F5F9),
        selectedItemColor: const Color(0xFF313A5F),
        unselectedItemColor: const Color(0xFF9CA3AF),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        type: BottomNavigationBarType.fixed,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: StreamBuilder<int>(
              stream: _unreadBubbleStream(),
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
            label: 'Mensagens',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.groups_rounded),
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
