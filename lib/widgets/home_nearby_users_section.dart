import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../pages/nearby_users_page.dart';
import 'home_section_header.dart';

/// Novos usuários perto de você — somente vitrine; chat segue regras existentes.
class HomeNearbyUsersSection extends StatelessWidget {
  const HomeNearbyUsersSection({
    super.key,
    required this.countryCode,
    required this.countryName,
    this.city,
    this.limit = 12,
  });

  final String countryCode;
  final String countryName;
  final String? city;
  final int limit;

  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);

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

  bool _matchesCity(Map<String, dynamic> data) {
    final normalizedCity = city?.trim().toLowerCase() ?? '';
    if (normalizedCity.isEmpty) return true;
    final userCity = (data['city'] ?? data['cityName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (userCity.isEmpty) return true;
    return userCity == normalizedCity;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String myUid, {
    required bool strictCity,
  }) {
    final normalizedCountry = countryCode.trim().toLowerCase();

    final filtered = docs.where((doc) {
      if (doc.id == myUid) return false;
      final data = doc.data();
      if (strictCity && !_matchesCity(data)) return false;
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

    if (filtered.length <= limit) return filtered;
    return filtered.sublist(0, limit);
  }

  String _flagEmoji(String code) {
    final upper = code.trim().toUpperCase();
    if (upper.length != 2) return '🏳️';
    final first = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCodes([first, second]);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final normalizedCountry = countryCode.trim().toLowerCase();

    if (normalizedCountry.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: t.get('home_nearby_users'),
          seeAllLabel: t.get('home_see_all'),
          leading: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.person_add_alt_1_outlined,
              size: 16,
              color: Color(0xFF16A34A),
            ),
          ),
          onSeeAll: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NearbyUsersPage(
                  countryCode: countryCode,
                  countryName: countryName,
                  flag: _flagEmoji(countryCode),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('publicUsers')
              .where('countryCode', isEqualTo: normalizedCountry)
              .limit(60)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const SizedBox(
                height: 110,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final allDocs = snapshot.data?.docs ?? [];
            var docs = _filterDocs(allDocs, myUid, strictCity: true);
            if (docs.isEmpty && (city?.trim().isNotEmpty ?? false)) {
              docs = _filterDocs(allDocs, myUid, strictCity: false);
            }

            if (docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  t.get('home_nearby_users_empty'),
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              );
            }

            return SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final name = (data['name'] ?? t.get('user')).toString();
                  final photoUrl = (data['photoUrl'] ?? '').toString().trim();
                  final createdAt = data['createdAt'] is Timestamp
                      ? data['createdAt'] as Timestamp
                      : null;
                  final updatedAt = data['updatedAt'] is Timestamp
                      ? data['updatedAt'] as Timestamp
                      : null;
                  final initial =
                      name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

                  return InkWell(
                    onTap: () {
                      NearbyUsersPage.openChat(
                        context,
                        otherUid: doc.id,
                        otherName: name,
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 88,
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: const Color(0xFFE8ECF5),
                                backgroundImage: photoUrl.isNotEmpty
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: photoUrl.isEmpty
                                    ? Text(
                                        initial,
                                        style: const TextStyle(
                                          color: Color(0xFF313A5F),
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
                          const SizedBox(height: 6),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _text,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _joinedLabel(createdAt, updatedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
