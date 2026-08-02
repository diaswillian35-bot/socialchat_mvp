import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'create_group_page.dart';
import 'group_chat_page.dart';
import '../l10n/app_texts.dart';
import '../services/group_discovery_logic.dart';
import '../services/group_discovery_service.dart';
import '../services/group_lifecycle_service.dart';
import '../services/group_location_normalize.dart';
import '../services/groups_list_logic.dart';
import '../services/iso_country_names.dart';
import '../services/premium_access_service.dart';

class GroupsListPage extends StatefulWidget {
  const GroupsListPage({super.key});

  @override
  State<GroupsListPage> createState() => GroupsListPageState();
}

class _TabCache {
  List<GroupDiscoveryItem> items = [];
  GroupDiscoveryCursor? cursor;
  bool hasMore = true;
  bool loading = false;
  bool loadingMore = false;
  Object? error;
  String cacheKey = '';
  bool loadedOnce = false;
}

class GroupsListPageState extends State<GroupsListPage> {
  final TextEditingController _searchC = TextEditingController();
  final GroupDiscoveryService _discovery = GroupDiscoveryService();
  final ScrollController _scrollC = ScrollController();

  GroupDiscoveryTab _tab = GroupDiscoveryTab.mine;
  final Map<GroupDiscoveryTab, _TabCache> _caches = {
    for (final t in GroupDiscoveryTab.values) t: _TabCache(),
  };

  bool _showBanner = true;
  String _myCityKey = '';
  String _myCountryCode = '';
  double? _myCityLatitude;
  double? _myCityLongitude;
  bool _profileLoaded = false;
  int _retryToken = 0;
  Set<String> _pendingIds = {};
  String _loadedLocaleCode = '';
  // Premium ainda é lido do perfil (join internacional / chat); descoberta
  // geográfica usa sempre o país do usuário.
  // ignore: unused_field
  bool _isPremium = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _scrollC.addListener(_onScroll);
    _loadProfile();
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showBanner = false);
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
    _scrollC.dispose();
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final myUid = _uid;
    if (myUid == null) {
      if (mounted) setState(() => _profileLoaded = true);
      return;
    }

    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(myUid).get();
      final data = snap.data() ?? {};

      final city = (data['city'] ?? data['cityName'] ?? '').toString().trim();
      final code = GroupLocationNormalize.countryCode(
        data['homeCountryCode'] ?? data['countryCode'] ?? data['country'],
      );
      final latRaw = data['cityLat'] ?? data['lat'] ?? data['latitude'];
      final lngRaw = data['cityLng'] ?? data['lng'] ?? data['longitude'];
      final cityLat =
          latRaw is num ? latRaw.toDouble() : double.tryParse('$latRaw');
      final cityLng =
          lngRaw is num ? lngRaw.toDouble() : double.tryParse('$lngRaw');

      final pending = await _discovery.loadPendingGroupIds(myUid);

      if (!mounted) return;
      setState(() {
        _myCityKey = GroupLocationNormalize.cityKey(
          data['cityKey'] ?? city,
        );
        _myCountryCode = code;
        _myCityLatitude = cityLat;
        _myCityLongitude = cityLng;
        _isPremium = PremiumAccessService.isPremiumActiveFromData(data);
        _pendingIds = pending;
        _profileLoaded = true;
      });
      await _ensureTabLoaded(_tab, force: true);
    } catch (_) {
      if (mounted) {
        setState(() => _profileLoaded = true);
        await _ensureTabLoaded(_tab, force: true);
      }
    }
  }

  String _keyFor(GroupDiscoveryTab tab) {
    return GroupDiscoveryLogic.cacheKey(
      tab: tab,
      uid: _uid ?? '',
      countryCode: _myCountryCode,
      cityKey: _myCityKey,
      cityLatitude: _myCityLatitude,
      cityLongitude: _myCityLongitude,
      retryToken: _retryToken,
    );
  }

  /// Recarrega Meus grupos (ex.: após criar via FAB do shell).
  Future<void> reloadMine({bool selectMine = true}) async {
    if (!mounted) return;
    if (selectMine && _tab != GroupDiscoveryTab.mine) {
      setState(() => _tab = GroupDiscoveryTab.mine);
    }
    final cache = _caches[GroupDiscoveryTab.mine]!;
    cache.cacheKey = '';
    cache.loadedOnce = false;
    cache.loading = false;
    cache.error = null;
    await _ensureTabLoaded(GroupDiscoveryTab.mine, force: true);
  }

  Future<void> _ensureTabLoaded(
    GroupDiscoveryTab tab, {
    bool force = false,
  }) async {
    if (!_profileLoaded) return;

    final cache = _caches[tab]!;
    final key = _keyFor(tab);

    if (!force && cache.loadedOnce && cache.cacheKey == key && !cache.loading) {
      return;
    }

    if (force) {
      // Evita spinner eterno / early-return quando um fetch anterior ficou preso.
      cache.loading = false;
      cache.loadedOnce = false;
    }

    if (cache.cacheKey != key) {
      cache.items = [];
      cache.cursor = null;
      cache.hasMore = true;
      cache.error = null;
      cache.loadedOnce = false;
      cache.cacheKey = key;
    }

    if (cache.loading) return;

    final locationOk = GroupDiscoveryLogic.locationComplete(
      tab: tab,
      countryCode: _myCountryCode,
      cityKey: _myCityKey,
      cityLatitude: _myCityLatitude,
      cityLongitude: _myCityLongitude,
    );
    if (!locationOk && GroupDiscoveryLogic.needsLocation(tab)) {
      setState(() {
        cache.loading = false;
        cache.loadedOnce = true;
        cache.items = [];
        cache.error = null;
      });
      return;
    }

    setState(() {
      cache.loading = true;
      cache.error = null;
    });

    try {
      final page = await _fetchPage(tab, startAfter: null);
      if (!mounted) return;
      // Troca rápida de abas / retry: só aplica se a chave ainda for a mesma.
      if (cache.cacheKey != key) return;

      setState(() {
        cache.items = page.items;
        cache.cursor = page.cursor;
        cache.hasMore = page.hasMore;
        cache.loading = false;
        cache.loadedOnce = true;
        cache.error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (cache.cacheKey != key) return;
      setState(() {
        cache.loading = false;
        cache.loadedOnce = true;
        cache.error = e;
      });
    }
  }

  Future<GroupDiscoveryPage> _fetchPage(
    GroupDiscoveryTab tab, {
    GroupDiscoveryCursor? startAfter,
  }) {
    final uid = _uid ?? '';
    if (tab == GroupDiscoveryTab.mine) {
      return _discovery.fetchMine(uid: uid, startAfter: startAfter);
    }
    return _discovery.fetchDiscovery(
      tab: tab,
      uid: uid,
      countryCode: _myCountryCode,
      cityKey: _myCityKey,
      userCityLatitude: _myCityLatitude,
      userCityLongitude: _myCityLongitude,
      pendingIds: _pendingIds,
      startAfter: startAfter,
    );
  }

  Future<void> _loadMore() async {
    final cache = _caches[_tab]!;
    if (cache.loading || cache.loadingMore || !cache.hasMore) return;
    if (cache.cursor == null && cache.items.isNotEmpty) return;

    setState(() => cache.loadingMore = true);
    try {
      final page = await _fetchPage(_tab, startAfter: cache.cursor);
      if (!mounted) return;
      setState(() {
        final seen = cache.items.map((e) => e.id).toSet();
        for (final item in page.items) {
          if (!seen.contains(item.id)) cache.items.add(item);
        }
        cache.cursor = page.cursor ?? cache.cursor;
        cache.hasMore = page.hasMore;
        cache.loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => cache.loadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scrollC.hasClients) return;
    final pos = _scrollC.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  void _selectTab(GroupDiscoveryTab tab) {
    if (_tab == tab) {
      // Toque de novo na aba ativa: força refresh (evita lista vazia stale).
      _ensureTabLoaded(tab, force: true);
      return;
    }
    setState(() => _tab = tab);
    // Sempre refetch ao trocar de aba — IndexedStack mantém cache em memória.
    _ensureTabLoaded(tab, force: true);
  }

  void _retry() {
    setState(() {
      _retryToken++;
      for (final c in _caches.values) {
        c.cacheKey = '';
        c.loadedOnce = false;
        c.error = null;
      }
    });
    _ensureTabLoaded(_tab, force: true);
  }

  Future<void> _refreshAfterMembershipChange({
    required String groupId,
    required bool nowMember,
    bool pending = false,
  }) async {
    // Só move após confirmação: membro sai da descoberta e entra em Meus.
    setState(() {
      if (nowMember) {
        _pendingIds.remove(groupId);
        for (final tab in [
          GroupDiscoveryTab.city,
          GroupDiscoveryTab.region,
          GroupDiscoveryTab.country,
        ]) {
          _caches[tab]!.items.removeWhere((e) => e.id == groupId);
        }
        // Invalida Meus grupos para refletir o novo membro.
        _caches[GroupDiscoveryTab.mine]!.cacheKey = '';
        _caches[GroupDiscoveryTab.mine]!.loadedOnce = false;
      } else if (pending) {
        _pendingIds.add(groupId);
        for (final tab in [
          GroupDiscoveryTab.city,
          GroupDiscoveryTab.region,
          GroupDiscoveryTab.country,
        ]) {
          final list = _caches[tab]!.items;
          for (var i = 0; i < list.length; i++) {
            if (list[i].id == groupId) {
              list[i] = GroupDiscoveryItem(
                id: list[i].id,
                data: list[i].data,
                isPending: true,
              );
            }
          }
        }
      } else {
        _pendingIds.remove(groupId);
        for (final tab in [
          GroupDiscoveryTab.city,
          GroupDiscoveryTab.region,
          GroupDiscoveryTab.country,
        ]) {
          final list = _caches[tab]!.items;
          for (var i = 0; i < list.length; i++) {
            if (list[i].id == groupId) {
              list[i] = GroupDiscoveryItem(
                id: list[i].id,
                data: list[i].data,
                isPending: false,
              );
            }
          }
        }
      }
    });
    if (nowMember && _tab == GroupDiscoveryTab.mine) {
      await _ensureTabLoaded(GroupDiscoveryTab.mine, force: true);
    }
  }

  Future<void> _openCreate() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupPage()),
    );
    if (!mounted) return;
    await reloadMine(selectMine: true);
  }

  Future<void> _openGroup(GroupDiscoveryItem item) async {
    final name =
        (item.data['name'] ?? AppTexts.current.get('group')).toString().trim();
    final wasMember = item.isMember ||
        GroupDiscoveryLogic.isParticipating(
          data: item.data,
          uid: _uid ?? '',
        );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          groupId: item.id,
          groupName: name.isEmpty ? AppTexts.current.get('group') : name,
        ),
      ),
    );

    if (!mounted) return;

    // Revalida membership/pendência após voltar do chat/join.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(item.id)
          .get();
      if (!doc.exists) {
        setState(() {
          for (final c in _caches.values) {
            c.items.removeWhere((e) => e.id == item.id);
          }
        });
        return;
      }
      final data = doc.data() ?? {};
      final uid = _uid ?? '';
      final nowMember =
          GroupDiscoveryLogic.isParticipating(data: data, uid: uid);
      var pending = false;
      if (!nowMember && uid.isNotEmpty) {
        final p = await FirebaseFirestore.instance
            .collection('groups')
            .doc(item.id)
            .collection('pendingRequests')
            .doc(uid)
            .get();
        pending = p.exists && (p.data()?['status'] ?? '') == 'pending';
      }

      if (nowMember && !wasMember) {
        await _refreshAfterMembershipChange(
          groupId: item.id,
          nowMember: true,
        );
      } else if (!nowMember && pending) {
        await _refreshAfterMembershipChange(
          groupId: item.id,
          nowMember: false,
          pending: true,
        );
      } else if (!nowMember && !pending && item.isPending) {
        await _refreshAfterMembershipChange(
          groupId: item.id,
          nowMember: false,
          pending: false,
        );
      } else if (!nowMember && wasMember) {
        // Saiu do grupo: remove de Meus e invalida descoberta.
        setState(() {
          _caches[GroupDiscoveryTab.mine]!
              .items
              .removeWhere((e) => e.id == item.id);
          for (final t in [
            GroupDiscoveryTab.city,
            GroupDiscoveryTab.region,
            GroupDiscoveryTab.country,
          ]) {
            _caches[t]!.cacheKey = '';
            _caches[t]!.loadedOnce = false;
          }
        });
        await _ensureTabLoaded(_tab, force: true);
      }
    } catch (_) {
      // Rede: mantém UI atual; retry manual disponível.
    }
  }

  Future<void> _showGroupActions({
    required String groupId,
    required Map<String, dynamic> data,
  }) async {
    final t = AppTexts.current;
    final myUid = _uid;
    if (myUid == null) return;

    final isOwner = (data['ownerId'] ?? '').toString() == myUid;
    final isMember = GroupDiscoveryLogic.isParticipating(
      data: data,
      uid: myUid,
    );
    if (!isMember) return;

    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              if (isOwner)
                ListTile(
                  leading:
                      Icon(Icons.delete_outline_rounded, color: scheme.primary),
                  title: Text(
                    t.get('deleteGroup'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _deleteGroupFromList(groupId: groupId);
                  },
                ),
              if (!isOwner)
                ListTile(
                  leading: Icon(Icons.logout_rounded, color: scheme.primary),
                  title: Text(
                    t.get('leaveGroup'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _leaveGroupFromList(groupId: groupId);
                  },
                ),
              ListTile(
                leading:
                    Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                title: Text(
                  t.get('cancel'),
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteGroupFromList({required String groupId}) async {
    final t = AppTexts.current;
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.get('deleteGroup')),
        content: Text(t.get('group_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.get('delete')),
          ),
        ],
      ),
    );
    if (confirm1 != true) return;

    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.get('deleteGroup')),
        content: Text(t.get('group_delete_confirm_final')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.get('delete')),
          ),
        ],
      ),
    );
    if (confirm2 != true) return;

    try {
      await GroupLifecycleService.deleteGroup(groupId: groupId);
      if (!mounted) return;
      setState(() {
        for (final c in _caches.values) {
          c.items.removeWhere((e) => e.id == groupId);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.get('group_deleted_success'))),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${t.get(GroupLifecycleService.deleteErrorKey(e))}: ${e.message ?? e.code}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.get('group_delete_error')}: $e')),
      );
    }
  }

  Future<void> _leaveGroupFromList({required String groupId}) async {
    final t = AppTexts.current;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.get('leaveGroup')),
        content: Text(t.get('group_leave_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.get('leave')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await GroupLifecycleService.leaveGroup(groupId: groupId);
      if (!mounted) return;
      setState(() {
        _caches[GroupDiscoveryTab.mine]!
            .items
            .removeWhere((e) => e.id == groupId);
        for (final t in [
          GroupDiscoveryTab.city,
          GroupDiscoveryTab.region,
          GroupDiscoveryTab.country,
        ]) {
          _caches[t]!.cacheKey = '';
          _caches[t]!.loadedOnce = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.get('group_left_success'))),
      );
      await _ensureTabLoaded(_tab, force: true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${t.get(GroupLifecycleService.leaveErrorKey(e))}: ${e.message ?? e.code}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.get('group_leave_error')}: $e')),
      );
    }
  }

  int _membersCount(Map<String, dynamic> data) {
    final m = data['members'];
    if (m is List) return m.length;
    final mc = data['membersCount'];
    if (mc is int) return mc;
    if (mc is num) return mc.toInt();
    return 0;
  }

  int _readMyUnread(Map<String, dynamic> data, String myUid) {
    final unreadRaw = data['unread'];
    if (unreadRaw is Map && unreadRaw.containsKey(myUid)) {
      final value = unreadRaw[myUid];
      if (value is int) return value;
      if (value is num) return value.toInt();
    }
    return 0;
  }

  String _prettyCountry(String s) {
    final code = GroupLocationNormalize.countryCode(s);
    if (code.isEmpty) return '--';
    final lang = Localizations.localeOf(context).toLanguageTag();
    return IsoCountryNames.displayName(code, lang);
  }

  String _groupLocationLabel(
    Map<String, dynamic> data,
    AppTexts t,
  ) {
    final location = GroupDiscoveryLogic.cardLocation(data);
    final countryRaw = location.country;
    final country = countryRaw.isEmpty ? '--' : _prettyCountry(countryRaw);

    if (location.countryOnly) {
      // Grupo nacional nunca expõe cidade, estado ou região.
      return country;
    }

    if (location.scope == 'region') {
      final centerCity = location.city;
      if (centerCity.isEmpty) return country;
      final regionOf =
          t.get('groups_region_of_city').replaceAll('{city}', centerCity);
      return '$regionOf · $country';
    }

    final city = location.city;
    return '${city.isEmpty ? '--' : city} · $country';
  }

  List<GroupDiscoveryItem> _visibleItems(_TabCache cache) {
    final q = _searchC.text.trim().toLowerCase();
    if (q.isEmpty) return cache.items;
    return cache.items.where((item) {
      final data = item.data;
      final name = (data['name'] ?? '').toString().toLowerCase();
      final bio = (data['bio'] ?? '').toString().toLowerCase();
      final city =
          (data['city'] ?? data['cityName'] ?? '').toString().toLowerCase();
      final country = (data['country'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          bio.contains(q) ||
          city.contains(q) ||
          country.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final scheme = Theme.of(context).colorScheme;
    final cache = _caches[_tab]!;
    final locationOk = GroupDiscoveryLogic.locationComplete(
      tab: _tab,
      countryCode: _myCountryCode,
      cityKey: _myCityKey,
      cityLatitude: _myCityLatitude,
      cityLongitude: _myCityLongitude,
    );

    final uiState = GroupDiscoveryLogic.decideState(
      profileLoaded: _profileLoaded,
      locationOk: locationOk || !GroupDiscoveryLogic.needsLocation(_tab),
      loading: !_profileLoaded || (cache.loading && !cache.loadedOnce),
      hasError: cache.error != null,
      hasItems: cache.items.isNotEmpty,
    );

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          t.get('groups'),
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            tooltip: t.get('create_group_title'),
            onPressed: _openCreate,
            icon: Icon(Icons.add_rounded, color: scheme.primary),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_showBanner)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: _topBanner(scheme, t),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _searchField(scheme, t),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _selectors(scheme, t),
            ),
            Expanded(child: _bodyForState(uiState, cache, scheme, t)),
          ],
        ),
      ),
    );
  }

  Widget _topBanner(ColorScheme scheme, AppTexts t) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.primary.withValues(alpha: 0.85)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_rounded, color: scheme.onPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t.get('groups_banner_text'),
              style: TextStyle(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(ColorScheme scheme, AppTexts t) {
    return TextField(
      controller: _searchC,
      onChanged: (_) => setState(() {}),
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        hintText: t.get('search_groups_city_country'),
        prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
        suffixIcon: _searchC.text.trim().isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchC.clear();
                  setState(() {});
                },
                icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
              ),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary),
        ),
      ),
    );
  }

  Widget _selectors(ColorScheme scheme, AppTexts t) {
    return Semantics(
      label: t.get('groups_tabs_a11y'),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: GroupDiscoveryTab.values.map((tab) {
            final selected = _tab == tab;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                button: true,
                selected: selected,
                label: t.get(GroupDiscoveryLogic.tabSemanticsKey(tab)),
                child: Material(
                  color: selected
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _selectTab(tab),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color:
                              selected ? scheme.primary : scheme.outlineVariant,
                        ),
                      ),
                      child: Text(
                        t.get(GroupDiscoveryLogic.tabLabelKey(tab)),
                        style: TextStyle(
                          color: selected ? scheme.onPrimary : scheme.onSurface,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _bodyForState(
    GroupDiscoveryUiState state,
    _TabCache cache,
    ColorScheme scheme,
    AppTexts t,
  ) {
    switch (state) {
      case GroupDiscoveryUiState.loading:
        return const Center(child: CircularProgressIndicator());
      case GroupDiscoveryUiState.locationIncomplete:
        return _messageState(
          t.get('groups_need_location'),
          scheme,
          retry: false,
        );
      case GroupDiscoveryUiState.error:
        return _messageState(
          t.get(GroupsListLogic.errorMessageKey(cache.error)),
          scheme,
          retry: true,
        );
      case GroupDiscoveryUiState.empty:
        return _messageState(
          t.get(GroupDiscoveryLogic.emptyMessageKey(_tab)),
          scheme,
          retry: false,
        );
      case GroupDiscoveryUiState.list:
        final items = _visibleItems(cache);
        if (items.isEmpty && _searchC.text.trim().isNotEmpty) {
          return _messageState(t.get('no_groups_found'), scheme, retry: false);
        }
        return ListView.builder(
          controller: _scrollC,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: items.length + (cache.loadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _groupCard(items[index], scheme, t);
          },
        );
    }
  }

  Widget _messageState(
    String message,
    ColorScheme scheme, {
    required bool retry,
  }) {
    final t = AppTexts.current;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (retry) ...[
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _retry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(t.get('user_search_retry')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _groupCard(
    GroupDiscoveryItem item,
    ColorScheme scheme,
    AppTexts t,
  ) {
    final data = item.data;
    final name = (data['name'] ?? t.get('group')).toString().trim();
    final bio = (data['bio'] ?? '').toString().trim();
    final locationLabel = _groupLocationLabel(data, t);
    final members = _membersCount(data);
    final myUid = _uid;
    final isMember = item.isMember ||
        (myUid != null &&
            GroupDiscoveryLogic.isParticipating(data: data, uid: myUid));
    final pending = item.isPending && !isMember;
    final myUnread = myUid == null ? 0 : _readMyUnread(data, myUid);
    final hasUnread = myUnread > 0 && isMember;
    final avatarUrl = (data['avatarUrl'] ?? '').toString().trim();

    String actionLabel;
    if (isMember) {
      actionLabel = t.get('open');
    } else if (pending) {
      actionLabel = t.get('groups_request_pending');
    } else {
      actionLabel = t.get('preview');
    }

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openGroup(item),
      onLongPress: isMember
          ? () => _showGroupActions(groupId: item.id, data: data)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: avatarUrl.isNotEmpty
                    ? Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.groups_rounded, color: scheme.primary),
                      )
                    : Icon(Icons.groups_rounded, color: scheme.primary),
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
                          name.isEmpty ? t.get('group') : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            myUnread > 99 ? '99+' : '$myUnread',
                            style: TextStyle(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$members ${members == 1 ? t.get('member') : t.get('members')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      bio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Opacity(
                        opacity: pending ? 0.7 : 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: isMember || pending
                                ? scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5)
                                : scheme.primary,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isMember || pending
                                  ? scheme.outlineVariant
                                  : scheme.primary,
                            ),
                          ),
                          child: Text(
                            actionLabel,
                            style: TextStyle(
                              color: isMember || pending
                                  ? scheme.onSurfaceVariant
                                  : scheme.onPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
