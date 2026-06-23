import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';

class SystemInboxPage extends StatefulWidget {
  const SystemInboxPage({super.key});

  @override
  State<SystemInboxPage> createState() => _SystemInboxPageState();
}

class _SystemInboxPageState extends State<SystemInboxPage> {
  String _loadedLocaleCode = '';

  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _inboxRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('systemInbox');

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

  Future<void> _markAllAsRead(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final batch = FirebaseFirestore.instance.batch();

    for (final doc in docs) {
      final data = doc.data();
      final isRead = data['isRead'] == true;
      if (!isRead) {
        batch.set(
          doc.reference,
          {
            'isRead': true,
            'readAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    }

    await batch.commit();
  }

  String _formatDate(dynamic raw) {
    if (raw is! Timestamp) return '-';
    final d = raw.toDate();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  IconData _typeIcon(String type) {
  switch (type) {
    case 'warning':
      return Icons.warning_amber_rounded;
    case 'premium':
      return Icons.star_rounded;
    case 'update':
      return Icons.system_update_alt_rounded;
    default:
      return Icons.notifications_none_rounded;
  }
}


Color _typeColor(String type) {
  switch (type) {
    case 'warning':
      return Colors.orange;
    case 'premium':
      return Colors.amber.shade800;
    case 'update':
      return Colors.blue;
    default:
      return _muted;
  }
}

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          t.get('remdy_notices'),
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _inboxRef.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}'));
          }

          final docs = snap.data?.docs ?? [];

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (docs.isNotEmpty) {
              _markAllAsRead(docs);
            }
          });

          if (docs.isEmpty) {
            return Center(
              child: Text(
                t.get('no_notices_yet'),
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();

              final title = (data['title'] ?? '').toString().trim();
              final body = (data['body'] ?? '').toString().trim();
              final type = (data['type'] ?? 'info').toString().trim();
              final isRead = data['isRead'] == true;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isRead ? Colors.white : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isRead ? _border : _typeColor(type).withOpacity(0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _typeColor(type).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _typeIcon(type),
                        color: _typeColor(type),
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
                                  title.isEmpty ? t.get('notice') : title,
                                  style: const TextStyle(
                                    color: _text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            body.isEmpty ? '-' : body,
                            style: const TextStyle(
                              color: _text,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatDate(data['createdAt']),
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
