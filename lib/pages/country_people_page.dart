import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/remdy_launch_access.dart';
import '../widgets/publish_cta_card.dart';
import '../services/explore_only.dart';
import '../services/nearby_visibility.dart';
import '../services/user_interests.dart';
import '../widgets/common_carousel.dart';
import '../widgets/explore_only_bar.dart';
import '../l10n/app_texts.dart';
import '../services/block_service.dart';
import '../services/international_chat_service.dart';
import '../services/invite_share_text.dart';
import '../services/event_share_image_service.dart' show EventShareOrigin;
import '../services/people_country_hierarchy.dart';
import '../services/people_country_view.dart';
import '../services/presence_online_set.dart';
import '../services/user_avatar_resolver.dart';
import '../services/user_location_scope.dart';
import '../utils/user_search_normalize.dart';
import '../widget/online_dot.dart';
import '../widgets/remdy_keyboard_caps.dart';
import '../widgets/blocked_uids_builder.dart';
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
    this.viewerCountryCode = '',
  });

  final String countryCode;
  final String countryName;
  final String flag;

  /// País de casa de quem está vendo (faixa do lançamento em país de fora).
  final String viewerCountryCode;

  /// Chave da faixa "conversar com pessoas de ... está grátis", ou null
  /// quando é o próprio país.
  static String? launchBannerKey({
    required String viewerCountryCode,
    required String targetCountryCode,
  }) {
    final v = viewerCountryCode.trim().toLowerCase();
    final c = targetCountryCode.trim().toLowerCase();
    if (c.isEmpty || v == c) return null;
    switch (v) {
      case 'br':
      case 'ca':
      case 'pt':
        return 'launch_free_chat_banner_$v';
      default:
        return 'launch_free_chat_banner';
    }
  }

  @override
  State<CountryPeoplePage> createState() => _CountryPeoplePageState();
}

class _CountryPeoplePageState extends State<CountryPeoplePage>
    with BlockedUidsListenable {
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
  Map<String, dynamic>? _viewerData;
  String? _stateFilter;
  bool _savingNearby = false;

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
    if (_myUid.isNotEmpty) {
      try {
        _viewerData = (await FirebaseFirestore.instance
                .collection('users')
                .doc(_myUid)
                .get())
            .data();
      } catch (_) {
        _viewerData = null;
      }
    }
    await _reload();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scrollC.hasClients) return;
    if (_scrollC.position.pixels < _scrollC.position.maxScrollExtent - 320) {
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
      if (UserSearchNormalize.isQueryReady(_query)) {
        while (_hasMore && _lastDoc != null) {
          final next = await _baseQuery().startAfterDocument(_lastDoc!).get();
          _ingest(next.docs, replace: false);
        }
      }
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
    if (blockedUids.contains(d.id)) return false;
    final data = d.data();
    if (!InternationalChatService.isActiveAccount(data)) return false;
    if (ExploreOnly.isExploreOnlyData(data)) return false;
    if (data['hiddenFromLists'] == true) return false;
    final code = InternationalChatService.readHomeCountryCode(data);
    if (code != _code) return false;
    if ((data['name'] ?? '').toString().trim().isEmpty) return false;
    // Ban / soft-delete / age gates covered by isActiveAccount when possible.
    if (data['isBanned'] == true || data['deleted'] == true) return false;
    if (data['suspended'] == true) return false;
    // Privacidade e idade continuam obrigatórias. Coordenadas ausentes só
    // retiram a classificação por distância; não apagam o perfil do país.
    if (data['ageVerificationStatus'] != 'verified') return false;
    if (data['profileComplete'] != true) return false;
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

  Future<void> _openChat(
      Map<String, dynamic> otherData, String otherUid) async {
    if (!await BlockService.allowOpenPeer(otherUid)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppTexts.current.get('chat_unavailable_blocked'))),
      );
      return;
    }
    final otherName =
        (otherData['name'] ?? AppTexts.current.get('user')).toString();
    final myData = await InternationalChatService.fetchActiveUserData(_myUid);
    if (myData == null ||
        !InternationalChatService.isActiveAccount(otherData)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppTexts.current.get('profile_no_longer_available'))),
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
    if (!await InternationalChatService.conversationExists(_myUid, otherUid) &&
        mounted &&
        await ExploreOnly.blocksNewChat(context, otherUid)) {
      return;
    }
    final convoId = await InternationalChatService.getOrCreateConversation(
        _myUid, otherUid);
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

  /// Barra de baixo: "Não quero conhecer ninguém, só usar o app".
  /// Mesma lógica do Editar perfil (users + publicUsers, presença).
  Future<void> _setExploreOnly(bool value) async {
    final uid = _myUid;
    if (uid.isEmpty || _savingNearby) return;
    final previous = _viewerData?['exploreOnly'] == true;
    if (previous == value) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _savingNearby = true;
      _viewerData = {...?_viewerData, 'exploreOnly': value};
    });
    try {
      await ExploreOnly.setMode(uid, value);
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(AppTexts.current.get(value
              ? 'people_explore_only_now_on'
              : 'people_explore_only_now_off')),
        ));
    } catch (e) {
      debugPrint('[CountryPeople] exploreOnly: $e');
      if (!mounted) return;
      setState(() {
        _viewerData = {...?_viewerData, 'exploreOnly': previous};
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(AppTexts.current.get('save_error')),
        ));
    } finally {
      if (mounted) setState(() => _savingNearby = false);
    }
  }

  void _invite() {
    final code = (_viewerData?['inviteCode'] ?? '').toString().trim();
    Share.share(
      InviteShareText.message(code),
      sharePositionOrigin: EventShareOrigin.fromContext(context),
    );
  }

  void _openProfile(String uid) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PublicProfilePage(userUid: uid)),
    );
  }

  String? get _launchBannerKey => RemdyLaunchAccess.isFreeBrazilLaunch
      ? CountryPeoplePage.launchBannerKey(
          viewerCountryCode: widget.viewerCountryCode,
          targetCountryCode: widget.countryCode,
        )
      : null;

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final scheme = Theme.of(context).colorScheme;
    final countLabel = _loading && _docs.isEmpty
        ? ''
        : t
            .get(_docs.length == 1 ? 'people_count_one' : 'people_count_many')
            .replaceAll('{count}', '${_docs.length}${_hasMore ? '+' : ''}');
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.flag} ${widget.countryName}',
              style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 20),
            ),
            if (countLabel.isNotEmpty)
              Text(countLabel,
                  style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
          ],
        ),
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchC,
              textCapitalization: RemdyKeyboardCaps.none,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: t.get('people_country_search_hint'),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_launchBannerKey != null)
            PublishCtaCard(
              key: const Key('people_launch_free_banner'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              icon: Icons.celebration_outlined,
              title: t.get('launch_free_chat_banner_title'),
              subtitle: t.get(_launchBannerKey!),
            ),
          Expanded(child: _buildBody(t)),
        ],
      ),
      bottomNavigationBar: ExploreOnlyBar(
        value: _viewerData?['exploreOnly'] == true,
        onChanged: _savingNearby || _myUid.isEmpty ? null : _setExploreOnly,
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
    return PresenceOnlineSetBuilder(
      uids: visible.map((doc) => doc.id).toSet(),
      builder: (context, onlineUids) => _content(t, visible, onlineUids),
    );
  }

  CountryPerson _toPerson(
      QueryDocumentSnapshot<Map<String, dynamic>> doc, Set<String> online) {
    final data = doc.data();
    final coords = UserLocationScope.resolveCanonicalCoords(data);
    return CountryPerson(
      uid: doc.id,
      name: (data['name'] ?? AppTexts.current.get('user')).toString(),
      city: UserLocationScope.cityNameFromUserData(data),
      subdivision: UserLocationScope.stateLabelFromUserData(data),
      countryCode: _code,
      latitude: coords?.latitude,
      longitude: coords?.longitude,
      online: online.contains(doc.id),
      hometownCity: (data['hometownCity'] ?? '').toString(),
      hometownSubdivision: (data['hometownState'] ?? '').toString(),
      hometownCountryCode: (data['hometownCountryCode'] ?? '').toString(),
      interests: UserInterests.fromUserData(data),
      hideInCity: NearbyVisibility.hideInCityFromData(data),
    );
  }

  Widget _content(
    AppTexts t,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> visible,
    Set<String> onlineUids,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final docs = {for (final doc in visible) doc.id: doc};
    final people = visible.map((d) => _toPerson(d, onlineUids)).toList();
    final searching = UserSearchNormalize.isQueryReady(_query);
    final view = CountryPeopleView.build(
      people: people,
      viewer: _viewerData,
      countryCode: _code,
      stateFilter: searching ? null : _stateFilter,
    );
    final children = <Widget>[];

    if (!searching && view.chips.length > 1) {
      children.add(_chipsRow(t, scheme, view.chips));
    }

    if (searching) {
      if (people.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(t.get('no_people_found'))),
        ));
      } else {
        children.add(_sectionTitle(scheme, t.get('user_search_results')));
        final rows = [
          ...view.nearby,
          ...view.ownStateRows,
          ...view.otherStates.expand((s) => s.rows),
        ];
        children.addAll(rows.map((r) => _personRow(t, scheme, r, docs)));
      }
    } else if (people.isEmpty) {
      children.add(_emptyCard(
          t,
          scheme,
          t
              .get('people_country_empty_title')
              .replaceAll('{place}', widget.countryName)));
    } else {
      if (view.common.isNotEmpty) {
        children.add(_sectionTitle(scheme, t.get('people_in_common')));
        children.add(CommonCarousel(items: [
          for (final m in view.common)
            CommonCarouselItem(
              uid: m.person.uid,
              name: m.person.name,
              reason: _shortReasonText(t, m),
              avatar: _Avatar(
                  uid: m.person.uid,
                  data: docs[m.person.uid]!.data(),
                  radius: 28),
              onTap: () => _openProfile(m.person.uid),
            ),
        ]));
      }
      if (view.nearby.isNotEmpty) {
        final city = view.referenceCity;
        final title = view.referenceIsHometown
            ? t.get('people_near_place').replaceAll('{city}', city)
            : (city.isEmpty
                ? t.get('people_near_you')
                : t.get('people_near_you_region').replaceAll('{city}', city));
        children.add(
            _sectionTitle(scheme, title, trailing: '${view.nearby.length}'));
        children.addAll(view.nearby.map((r) => _personRow(t, scheme, r, docs)));
      }
      if (view.ownStateRows.isNotEmpty) {
        children.add(_sectionTitle(
            scheme,
            t
                .get('people_other_cities_of_state')
                .replaceAll('{prep}', ptStatePreposition(view.ownStateKey))
                .replaceAll('{state}', view.ownStateLabel),
            trailing: '${view.ownStateRows.length}'));
        children.addAll(_cityGroups(t, scheme, 'own',
            CountryCitySection.group(view.ownStateRows), docs));
      }
      for (final s in view.otherStates) {
        children.add(PeopleStateSection(
          key: PageStorageKey('country-state-${s.key}'),
          title: s.isOther ? t.get('people_state_other') : s.label,
          countLabel: t
              .get(
                  s.rows.length == 1 ? 'people_count_one' : 'people_count_many')
              .replaceAll('{count}', '${s.rows.length}'),
          initiallyOpen: s.initiallyOpen,
          children: _cityGroups(t, scheme, s.key, s.cities, docs),
        ));
      }
      final place = view.hasReference && view.referenceCityEmpty
          ? view.referenceCity
          : '';
      children.add(_emptyCard(
        t,
        scheme,
        place.isNotEmpty
            ? t.get('people_country_empty_title').replaceAll('{place}', place)
            : t.get('people_invite_title'),
      ));
    }

    if (_loadingMore) {
      children.add(const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator())));
    } else if (_hasMore && !searching) {
      children.add(Padding(
          padding: const EdgeInsets.all(12),
          child: TextButton(
              onPressed: _loadMore, child: Text(t.get('events_load_more')))));
    }
    return ListView(
        controller: _scrollC,
        padding: const EdgeInsets.only(bottom: 24),
        children: children);
  }

  Widget _chipsRow(
      AppTexts t, ColorScheme scheme, List<CountryStateChip> chips) {
    Widget chip(String? key, String label) {
      final selected = (_stateFilter ?? '') == (key ?? '');
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          key: ValueKey('country-chip-${key ?? 'all'}'),
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => setState(() => _stateFilter = key),
          selectedColor: scheme.primary,
          backgroundColor: scheme.surfaceContainerHighest,
          side: BorderSide.none,
          shape: const StadiumBorder(),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        children: [
          chip(null, t.get('people_chip_all')),
          ...chips.map((c) =>
              chip(c.key, c.isOther ? t.get('people_state_other') : c.label)),
        ],
      ),
    );
  }

  Widget _sectionTitle(ColorScheme scheme, String text, {String? trailing}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface)),
            ),
            if (trailing != null)
              Text(trailing,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant)),
          ],
        ),
      );

  /// Motivo curto do carrossel "Em comum" (estilo stories).
  String _shortReasonText(AppTexts t, CommonMatch m) {
    switch (m.reason) {
      case CommonReason.sharedInterests:
        return UserInterests.shortReasonText(m.interests, t);
      case CommonReason.sameCity:
      case CommonReason.livesInYourHometown:
        return t
            .get('people_reason_short_same_city')
            .replaceAll('{city}', m.city);
      case CommonReason.sameHometown:
        return t
            .get('people_reason_short_hometown')
            .replaceAll('{city}', m.city);
    }
  }

  /// Cidades do estado: cabeçalho "Cidade · N" fechado (mesmo estilo das
  /// linhas de estado), até 5 pessoas e "Ver todas".
  List<Widget> _cityGroups(
      AppTexts t,
      ColorScheme scheme,
      String stateKey,
      List<CountryCitySection> cities,
      Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return [
      for (final c in cities)
        PeopleStateSection(
          key: PageStorageKey('country-city-$stateKey-${c.label}'),
          title: t
              .get('people_city_header')
              .replaceAll('{city}', c.label)
              .replaceAll('{count}', '${c.rows.length}'),
          countLabel: '',
          initiallyOpen: false,
          children: [
            PeopleCityList(
              key: PageStorageKey('country-city-all-$stateKey-${c.label}'),
              total: c.rows.length,
              seeAllLabel: t
                  .get('people_city_see_all')
                  .replaceAll('{count}', '${c.rows.length}'),
              rows: c.rows.map((r) => _personRow(t, scheme, r, docs)).toList(),
            ),
          ],
        ),
    ];
  }

  Widget _personRow(AppTexts t, ColorScheme scheme, CountryPeopleRow r,
      Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final doc = docs[r.person.uid]!;
    final km = r.distanceKm;
    final parts = <String>[
      if (r.cityLabel.isNotEmpty) r.cityLabel,
      if (km != null) '${km < 1 ? 1 : km.round()} km',
    ];
    return InkWell(
      key: ValueKey('country-person-${r.person.uid}'),
      onTap: () => _openProfile(r.person.uid),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            _Avatar(uid: r.person.uid, data: doc.data(), radius: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                          fontSize: 15)),
                  if (parts.isNotEmpty)
                    Text(parts.join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  if (r.isViewerHometown)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(t.get('people_your_hometown_tag'),
                          style: TextStyle(
                              color: scheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _openChat(doc.data(), r.person.uid),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.primary,
                side: BorderSide(color: scheme.primary),
                shape: const StadiumBorder(),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(t.get('people_say_hi'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(AppTexts t, ColorScheme scheme, String title) {
    return Container(
      key: const ValueKey('country-invite-card'),
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text(t.get('people_invite_subtitle'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _invite,
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            child: Text(t.get('people_invite_button')),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.uid, required this.data, required this.radius});
  final String uid;
  final Map<String, dynamic> data;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = UserAvatarResolver.resolve(data);
    final name = (data['name'] ?? '').toString();
    return Stack(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: scheme.primaryContainer,
          backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
          child: url.isEmpty
              ? Text(UserAvatarResolver.initialFor(name),
                  style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: radius * 0.8))
              : null,
        ),
        Positioned(right: 0, bottom: 0, child: OnlineDot(uid: uid)),
      ],
    );
  }
}

/// Estado com cabeçalho "São Paulo • 2 pessoas ›"; abre/fecha ao tocar.
/// Até [CountryCitySection.previewCount] pessoas e o botão "Ver todas".
class PeopleCityList extends StatefulWidget {
  const PeopleCityList({
    super.key,
    required this.total,
    required this.seeAllLabel,
    required this.rows,
  });
  final int total;
  final String seeAllLabel;
  final List<Widget> rows;

  @override
  State<PeopleCityList> createState() => PeopleCityListState();
}

class PeopleCityListState extends State<PeopleCityList> {
  late bool _all = (PageStorage.maybeOf(context)
          ?.readState(context, identifier: widget.key) as bool?) ??
      false;

  @override
  Widget build(BuildContext context) {
    final limit = CountryCitySection.previewCount;
    final showAll = _all || widget.rows.length <= limit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...(showAll ? widget.rows : widget.rows.take(limit)),
        if (!showAll)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton(
                onPressed: () {
                  setState(() => _all = true);
                  PageStorage.maybeOf(context)
                      ?.writeState(context, true, identifier: widget.key);
                },
                child: Text(widget.seeAllLabel),
              ),
            ),
          ),
      ],
    );
  }
}

class PeopleStateSection extends StatefulWidget {
  const PeopleStateSection({
    super.key,
    required this.title,
    required this.countLabel,
    required this.initiallyOpen,
    required this.children,
  });
  final String title;
  final String countLabel;
  final bool initiallyOpen;
  final List<Widget> children;

  @override
  State<PeopleStateSection> createState() => PeopleStateSectionState();
}

class PeopleStateSectionState extends State<PeopleStateSection> {
  late bool _open = (PageStorage.maybeOf(context)
          ?.readState(context, identifier: widget.key) as bool?) ??
      widget.initiallyOpen;

  void _toggle() {
    setState(() => _open = !_open);
    PageStorage.maybeOf(context)
        ?.writeState(context, _open, identifier: widget.key);
  }

  @override
  void didUpdateWidget(covariant PeopleStateSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyOpen && !oldWidget.initiallyOpen) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_open) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface)),
                  ),
                  Text(widget.countLabel,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant)),
                  Icon(Icons.expand_less_rounded,
                      size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          ...widget.children,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.title,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface)),
                ),
                Text(widget.countLabel,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant)),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
