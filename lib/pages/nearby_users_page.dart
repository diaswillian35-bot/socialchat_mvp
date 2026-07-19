import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import 'chat_page.dart';

/// Lista completa de novos usuários do país (ex.: Brasil — todos, sem filtro de cidade).
class NearbyUsersPage extends StatelessWidget {
  const NearbyUsersPage({
    super.key,
    required this.countryCode,
    required this.countryName,
    required this.flag,
  });

  final String countryCode;
  final String countryName;
  final String flag;

  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _primary = Color(0xFF313A5F);

  static String _pairKey(String a, String b) {
    final list = [a, b]..sort();
    return '${list[0]}_${list[1]}';
  }

  static Future<String> _getOrCreateConversation(String myUid, String otherUid) async {
    final db = FirebaseFirestore.instance;
    final key = _pairKey(myUid, otherUid);
    final ref = db.collection('conversations').doc(key);

    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'participants': [myUid, otherUid],
        'pairKey': key,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unread': {
          myUid: 0,
          otherUid: 0,
        },
      }, SetOptions(merge: true));
    }
    return ref.id;
  }

  static Future<void> openChat(
    BuildContext context, {
    required String otherUid,
    required String otherName,
  }) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid.isEmpty) return;

    try {
      final convoId = await _getOrCreateConversation(myUid, otherUid);
      if (!context.mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: convoId,
            otherUid: otherUid,
            otherName: otherName,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppTexts.t('error')}: $e')),
      );
    }
  }

  static String flagEmoji(String code) {
    final upper = code.trim().toUpperCase();
    if (upper.length != 2) return '🏳️';
    final first = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCodes([first, second]);
  }

  bool _isRecent(Map<String, dynamic> data) {
    final cutoff =
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30)));
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp && createdAt.compareTo(cutoff) >= 0) {
      return true;
    }
    final updatedAt = data['updatedAt'];
    if (createdAt == null &&
        updatedAt is Timestamp &&
        updatedAt.compareTo(cutoff) >= 0) {
      return true;
    }
    return createdAt == null && updatedAt == null;
  }

  String _joinedLabel(Timestamp? createdAt, Timestamp? updatedAt) {
    final reference = createdAt ?? updatedAt;
    if (reference == null) return AppTexts.t('home_new_user');

    final diff = DateTime.now().difference(reference.toDate());
    if (diff.inMinutes < 60) {
      return AppTexts.t('home_joined_minutes_ago').replaceAll(
        '{minutes}',
        '${diff.inMinutes.clamp(1, 59)}',
      );
    }
    if (diff.inHours < 24) {
      return AppTexts.t('home_joined_hours_ago').replaceAll(
        '{hours}',
        '${diff.inHours}',
      );
    }
    if (diff.inDays < 30) {
      return AppTexts.t('home_joined_days_ago').replaceAll(
        '{days}',
        '${diff.inDays}',
      );
    }
    return AppTexts.t('home_new_user');
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String myUid,
  ) {
    final normalizedCountry = countryCode.trim().toLowerCase();

    final filtered = docs.where((doc) {
      if (doc.id == myUid) return false;
      final data = doc.data();
      if (!_isRecent(data)) return false;

      final code = (data['countryCode'] ?? '').toString().trim().toLowerCase();
      if (normalizedCountry.isNotEmpty &&
          code.isNotEmpty &&
          code != normalizedCountry) {
        return false;
      }

      return (data['name'] ?? '').toString().trim().isNotEmpty;
    }).toList();

    filtered.sort((a, b) {
      final aTs = a.data()['createdAt'] ?? a.data()['updatedAt'];
      final bTs = b.data()['createdAt'] ?? b.data()['updatedAt'];
      if (aTs is Timestamp && bTs is Timestamp) {
        return bTs.compareTo(aTs);
      }
      return 0;
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final normalizedCountry = countryCode.trim().toLowerCase();
    final subtitle = t.get('nearby_users_all_in_country')
        .replaceAll('{flag}', flag)
        .replaceAll('{country}', countryName);

    if (normalizedCountry.isEmpty) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: _muted),
          title: Text(
            t.get('home_nearby_users'),
            style: const TextStyle(color: _text, fontWeight: FontWeight.w800),
          ),
        ),
        body: Center(child: Text(t.get('home_nearby_users_empty'))),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _muted),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.get('home_nearby_users'),
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                color: _muted,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('publicUsers')
            .where('countryCode', isEqualTo: normalizedCountry)
            .limit(120)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                '${t.get('error')}: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final docs = _filterDocs(snapshot.data?.docs ?? [], myUid);

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t.get('home_nearby_users_empty'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final name = (data['name'] ?? t.get('user')).toString();
              final photoUrl = (data['photoUrl'] ?? '').toString().trim();
              final city = (data['city'] ?? data['cityName'] ?? '').toString();
              final createdAt = data['createdAt'] is Timestamp
                  ? data['createdAt'] as Timestamp
                  : null;
              final updatedAt = data['updatedAt'] is Timestamp
                  ? data['updatedAt'] as Timestamp
                  : null;
              final initial =
                  name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => openChat(
                    context,
                    otherUid: doc.id,
                    otherName: name,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: const Color(0xFFE8ECF5),
                              backgroundImage:
                                  photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                              child: photoUrl.isEmpty
                                  ? Text(
                                      initial,
                                      style: const TextStyle(
                                        color: _primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF16A34A),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  t.get('home_new_badge'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
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
                                style: const TextStyle(
                                  color: _text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _joinedLabel(createdAt, updatedAt),
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (city.trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  city.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: _primary,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
