import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/block_service.dart';
import '../services/international_chat_service.dart';
import '../services/people_browse_config_service.dart';
import '../services/people_browse_grouping.dart';
import '../services/user_avatar_resolver.dart';
import '../widgets/international_premium_dialog.dart';
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

  /// Serializa taps concorrentes (double-tap) no mesmo UID.
  static final Set<String> _openingUids = <String>{};

  static Future<void> openChat(
    BuildContext context, {
    required String otherUid,
    required String otherName,
  }) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid.isEmpty) return;
    final target = otherUid.trim();
    if (target.isEmpty || target == myUid) return;
    if (!_openingUids.add(target)) return;

    try {
      final myData = await InternationalChatService.fetchActiveUserData(myUid);
      final otherData =
          await InternationalChatService.fetchActiveUserData(target);

      if (myData == null || otherData == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppTexts.t('profile_no_longer_available')),
            ),
          );
        }
        return;
      }

      final blocked = await BlockService.isEitherBlocked(target);
      if (blocked) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppTexts.t('chat_unavailable_blocked'))),
          );
        }
        return;
      }

      final canSend = InternationalChatService.canSendMessage(
        senderData: myData,
        recipientData: otherData,
      );

      if (!canSend) {
        final exists =
            await InternationalChatService.conversationExists(myUid, target);
        if (!exists) {
          if (context.mounted) {
            await InternationalPremiumDialog.showStart(context);
          }
          return;
        }
      }

      final convoId = await InternationalChatService.getOrCreateConversation(
          myUid, target);
      if (!context.mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: convoId,
            otherUid: target,
            otherName: otherName,
          ),
        ),
      );
    } on ConversationLookupException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTexts.t('user_search_conversation_lookup_error')),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppTexts.t('error')}: $e')),
      );
    } finally {
      _openingUids.remove(target);
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
      if (!InternationalChatService.isActiveAccount(data)) return false;
      if (!_isRecent(data)) return false;

      final code = InternationalChatService.readHomeCountryCode(data);
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
    final subtitle = t
        .get('nearby_users_all_in_country')
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
            .collection('users')
            .where('homeCountryCode', isEqualTo: normalizedCountry)
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

          return FutureBuilder<int>(
            future: PeopleBrowseConfigService.citySectionMinProfiles(),
            initialData:
                PeopleBrowseConfigService.cachedCitySectionMinProfiles,
            builder: (context, cfgSnap) {
              final minCity = cfgSnap.data ??
                  PeopleBrowseConfigService.defaultCitySectionMin;
              final profiles = docs.map((doc) {
                final data = doc.data();
                return PeopleBrowseProfile(
                  uid: doc.id,
                  name: (data['name'] ?? t.get('user')).toString(),
                  city: (data['cityName'] ?? data['city'] ?? '').toString(),
                  state:
                      (data['stateName'] ?? data['state'] ?? '').toString(),
                  photoUrl: UserAvatarResolver.resolve(data),
                  countryCode: countryCode,
                );
              }).toList();

              final groups = PeopleBrowseGrouping.group(
                profiles: profiles,
                citySectionMinProfiles: minCity,
                otherCitiesLabel: t.get('people_other_cities_in_state'),
              );

              final tiles = <Widget>[];
              for (final state in groups) {
                tiles.add(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    child: Text(
                      state.stateLabel,
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
                for (final section in state.sections) {
                  tiles.add(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                      child: Text(
                        section.title,
                        style: TextStyle(
                          color: section.isOtherCitiesBucket ? _muted : _primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                  for (final p in section.profiles) {
                    final data = docs.firstWhere((d) => d.id == p.uid).data();
                    final createdAt = data['createdAt'] is Timestamp
                        ? data['createdAt'] as Timestamp
                        : null;
                    final updatedAt = data['updatedAt'] is Timestamp
                        ? data['updatedAt'] as Timestamp
                        : null;
                    tiles.add(
                      _NearbyPersonTile(
                        profile: p,
                        joinedLabel: _joinedLabel(createdAt, updatedAt),
                        onTap: () => openChat(
                          context,
                          otherUid: p.uid,
                          otherName: p.name,
                        ),
                      ),
                    );
                    tiles.add(const SizedBox(height: 10));
                  }
                }
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: tiles,
              );
            },
          );
        },
      ),
    );
  }
}

class _NearbyPersonTile extends StatelessWidget {
  const _NearbyPersonTile({
    required this.profile,
    required this.joinedLabel,
    required this.onTap,
  });

  final PeopleBrowseProfile profile;
  final String joinedLabel;
  final VoidCallback onTap;

  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _primary = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final initial = UserAvatarResolver.initialFor(profile.name);
    final cityLine = PeopleBrowseGrouping.displayCityUnderName(profile);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                    backgroundImage: profile.photoUrl.isNotEmpty
                        ? NetworkImage(profile.photoUrl)
                        : null,
                    onBackgroundImageError:
                        profile.photoUrl.isNotEmpty ? (_, __) {} : null,
                    child: profile.photoUrl.isEmpty
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
                        border: Border.all(color: Colors.white, width: 1.5),
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
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (cityLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        cityLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      joinedLabel,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
  }
}
