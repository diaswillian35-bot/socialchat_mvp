import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/international_chat_service.dart';
import '../services/people_browse_config_service.dart';
import '../services/people_browse_grouping.dart';
import '../services/user_avatar_resolver.dart';
import '../utils/user_search_normalize.dart';
import '../widget/online_dot.dart';
import '../widgets/international_premium_dialog.dart';
import 'chat_page.dart';
import 'public_profile_page.dart';

/// Tela aberta pela bandeira: busca + organização estado/cidade.
class CountryPeoplePage extends StatefulWidget {
  const CountryPeoplePage({
    super.key,
    required this.countryCode,
    required this.countryName,
    required this.flag,
  });

  final String countryCode;
  final String countryName;
  final String flag;

  @override
  State<CountryPeoplePage> createState() => _CountryPeoplePageState();
}

class _CountryPeoplePageState extends State<CountryPeoplePage> {
  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _primary = Color(0xFF313A5F);
  static const Color _card = Colors.white;
  static const int _pageSize = 40;

  final _searchC = TextEditingController();
  final _scrollC = ScrollController();
  Timer? _debounce;

  String _query = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  Set<String> _blocked = {};

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _code => widget.countryCode.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _scrollC.addListener(_onScroll);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchC.dispose();
    _scrollC.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final me = FirebaseAuth.instance.currentUser?.uid;
      if (me != null) {
        final snap =
            await FirebaseFirestore.instance.collection('users').doc(me).get();
        final list = snap.data()?['blocked'];
        if (list is List) {
          _blocked = list.map((e) => e.toString()).toSet();
        }
      }
    } catch (_) {
      _blocked = {};
    }
    await _reload();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scrollC.hasClients) return;
    if (_scrollC.position.pixels <
        _scrollC.position.maxScrollExtent - 320) {
      return;
    }
    unawaited(_loadMore());
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final next = value.trim();
      if (next == _query) return;
      setState(() => _query = next);
      unawaited(_reload());
    });
  }

  Query<Map<String, dynamic>> _baseQuery() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('homeCountryCode', isEqualTo: _code)
        .orderBy(FieldPath.documentId)
        .limit(_pageSize);
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _docs.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    try {
      final snap = await _baseQuery().get();
      _ingest(snap.docs, replace: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _lastDoc == null) return;
    setState(() => _loadingMore = true);
    try {
      final snap = await _baseQuery().startAfterDocument(_lastDoc!).get();
      _ingest(snap.docs, replace: false);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _ingest(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> page, {
    required bool replace,
  }) {
    if (page.isEmpty) {
      _hasMore = false;
      if (replace) _docs.clear();
      return;
    }
    _lastDoc = page.last;
    _hasMore = page.length >= _pageSize;
    final next = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in page) {
      if (!_isEligible(d)) continue;
      next.add(d);
    }
    if (replace) {
      _docs
        ..clear()
        ..addAll(next);
    } else {
      final seen = _docs.map((e) => e.id).toSet();
      for (final d in next) {
        if (seen.add(d.id)) _docs.add(d);
      }
    }
  }

  bool _isEligible(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    if (d.id == _myUid) return false;
    if (_blocked.contains(d.id)) return false;
    final data = d.data();
    if (!InternationalChatService.isActiveAccount(data)) return false;
    final code = InternationalChatService.readHomeCountryCode(data);
    if (code != _code) return false;
    if ((data['name'] ?? '').toString().trim().isEmpty) return false;
    // Ban / soft-delete / age gates covered by isActiveAccount when possible.
    if (data['isBanned'] == true || data['deleted'] == true) return false;
    if (data['suspended'] == true) return false;
    return true;
  }

  bool _matchesQuery(Map<String, dynamic> data) {
    final q = UserSearchNormalize.normalize(_query);
    if (q.isEmpty) return true;
    if (!UserSearchNormalize.isQueryReady(_query)) return true;
    final name = UserSearchNormalize.normalize((data['name'] ?? '').toString());
    final city = UserSearchNormalize.normalize(
      (data['cityName'] ?? data['city'] ?? '').toString(),
    );
    final state = UserSearchNormalize.normalize(
      (data['stateName'] ?? data['state'] ?? '').toString(),
    );
    final citySearch =
        UserSearchNormalize.normalize((data['citySearch'] ?? '').toString());
    final regionSearch =
        UserSearchNormalize.normalize((data['regionSearch'] ?? '').toString());
    final nameSearch =
        UserSearchNormalize.normalize((data['nameSearch'] ?? '').toString());
    return name.contains(q) ||
        city.contains(q) ||
        state.contains(q) ||
        citySearch.contains(q) ||
        regionSearch.contains(q) ||
        nameSearch.contains(q);
  }

  Future<void> _openChat(Map<String, dynamic> otherData, String otherUid) async {
    final otherName = (otherData['name'] ?? AppTexts.current.get('user')).toString();
    final myData = await InternationalChatService.fetchActiveUserData(_myUid);
    if (myData == null || !InternationalChatService.isActiveAccount(otherData)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.current.get('profile_no_longer_available'))),
      );
      return;
    }
    final canSend = InternationalChatService.canSendMessage(
      senderData: myData,
      recipientData: otherData,
    );
    if (!canSend) {
      final exists =
          await InternationalChatService.conversationExists(_myUid, otherUid);
      if (!exists && mounted) {
        await InternationalPremiumDialog.showStart(context);
        return;
      }
    }
    final convoId =
        await InternationalChatService.getOrCreateConversation(_myUid, otherUid);
    if (!mounted) return;
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
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(
          '${widget.flag} ${widget.countryName}',
          style: const TextStyle(color: _text, fontWeight: FontWeight.w800),
        ),
        iconTheme: const IconThemeData(color: _muted),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchC,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: t.get('people_search_hint'),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: _card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Expanded(child: _buildBody(t)),
        ],
      ),
    );
  }

  Widget _buildBody(AppTexts t) {
    if (_loading && _docs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${t.get('error')}: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(
                  onPressed: _reload,
                  child: Text(t.get('user_search_retry')),
                ),
            ],
          ),
        ),
      );
    }

    final visible = _docs.where((d) => _matchesQuery(d.data())).toList();
    if (visible.isEmpty) {
      return Center(child: Text(t.get('no_people_found')));
    }

    return FutureBuilder<int>(
      future: PeopleBrowseConfigService.citySectionMinProfiles(),
      initialData: PeopleBrowseConfigService.cachedCitySectionMinProfiles,
      builder: (context, cfgSnap) {
        final minCity = cfgSnap.data ??
            PeopleBrowseConfigService.defaultCitySectionMin;
        final profiles = visible.map((doc) {
          final data = doc.data();
          return PeopleBrowseProfile(
            uid: doc.id,
            name: (data['name'] ?? t.get('user')).toString(),
            city: (data['cityName'] ?? data['city'] ?? '').toString(),
            state: (data['stateName'] ?? data['state'] ?? '').toString(),
            photoUrl: UserAvatarResolver.resolve(data),
            countryCode: _code,
          );
        }).toList();

        // Busca ativa: lista plana filtrada (cidade <30 ainda aparece).
        final searching = UserSearchNormalize.isQueryReady(_query);
        final groups = searching
            ? [
                PeopleBrowseStateGroup(
                  stateLabel: t.get('user_search_results'),
                  sections: [
                    PeopleBrowseCitySection(
                      title: '',
                      profiles: profiles,
                      isOtherCitiesBucket: true,
                    ),
                  ],
                ),
              ]
            : PeopleBrowseGrouping.group(
                profiles: profiles,
                citySectionMinProfiles: minCity,
                otherCitiesLabel: t.get('people_other_cities_in_state'),
              );

        final children = <Widget>[];
            for (final state in groups) {
              if (!searching) {
                children.add(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Text(
                      state.stateLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _text,
                      ),
                    ),
                  ),
                );
              }
              for (final section in state.sections) {
                if (!searching && section.title.isNotEmpty) {
                  children.add(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        section.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: section.isOtherCitiesBucket
                              ? _muted
                              : _primary,
                        ),
                      ),
                    ),
                  );
                }
                for (final p in section.profiles) {
                  final doc = visible.firstWhere((d) => d.id == p.uid);
                  children.add(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _PersonTile(
                        profile: p,
                        onProfile: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PublicProfilePage(userUid: p.uid),
                            ),
                          );
                        },
                        onChat: () => _openChat(doc.data(), p.uid),
                      ),
                    ),
                  );
                }
              }
            }
            if (_loadingMore) {
              children.add(
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            } else if (_hasMore && !searching) {
              children.add(
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextButton(
                    onPressed: _loadMore,
                    child: Text(t.get('events_load_more')),
                  ),
                ),
              );
            }

            return ListView(
              controller: _scrollC,
              padding: const EdgeInsets.only(bottom: 24),
              children: children,
            );
      },
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.profile,
    required this.onProfile,
    required this.onChat,
  });

  final PeopleBrowseProfile profile;
  final VoidCallback onProfile;
  final VoidCallback onChat;

  static const Color _primary = Color(0xFF313A5F);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _card = Colors.white;

  @override
  Widget build(BuildContext context) {
    final city = PeopleBrowseGrouping.displayCityUnderName(profile);
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onProfile,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFE5E7EB),
                    backgroundImage: profile.photoUrl.isNotEmpty
                        ? NetworkImage(profile.photoUrl)
                        : null,
                    child: profile.photoUrl.isEmpty
                        ? const Icon(Icons.person, color: _muted)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: OnlineDot(uid: profile.uid),
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
                        fontWeight: FontWeight.w800,
                        color: _text,
                        fontSize: 15,
                      ),
                    ),
                    if (city.isNotEmpty)
                      Text(
                        city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onChat,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                color: _primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
