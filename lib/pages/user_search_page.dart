import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/user_search_service.dart';
import '../utils/user_search_normalize.dart';
import 'nearby_users_page.dart';

/// Pesquisa global de usuários Remdy (nome / cidade / região / país).
class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key, this.searchService});

  final UserSearchService? searchService;

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final UserSearchDebounce _debounceHelper = UserSearchDebounce();

  late final UserSearchService _service =
      widget.searchService ?? UserSearchService();

  Timer? _debounce;
  UserSearchType _type = UserSearchType.name;
  String _activeQuery = '';
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  bool _showMinCharsHint = false;
  List<UserSearchHit> _hits = [];
  UserSearchCursor? _nextCursor;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore || _error != null) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 120) {
      _loadMore();
    }
  }

  void _resetResults({bool showMinChars = false}) {
    setState(() {
      _activeQuery = '';
      _hits = [];
      _hasMore = false;
      _error = null;
      _loading = false;
      _loadingMore = false;
      _showMinCharsHint = showMinChars;
      _nextCursor = null;
    });
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _debounceHelper.cancel();
      _resetResults();
      return;
    }

    if (!UserSearchNormalize.isQueryReady(trimmed)) {
      _debounceHelper.cancel();
      _resetResults(showMinChars: true);
      return;
    }

    setState(() {
      _showMinCharsHint = false;
      _loading = true;
      _error = null;
    });

    final token = _debounceHelper.schedule();
    _debounce = Timer(_debounceHelper.delay, () {
      if (!_debounceHelper.isCurrent(token)) return;
      _runSearch(trimmed, reset: true);
    });
  }

  void _onTypeChanged(UserSearchType type) {
    if (_type == type) return;
    _debounce?.cancel();
    setState(() => _type = type);
    final q = _controller.text.trim();
    if (UserSearchNormalize.isQueryReady(q)) {
      _runSearch(q, reset: true);
    } else {
      _resetResults(showMinChars: q.isNotEmpty);
    }
  }

  Future<void> _runSearch(String raw, {required bool reset}) async {
    if (_myUid == null) return;
    if (!UserSearchNormalize.isQueryReady(raw)) return;

    setState(() {
      if (reset) {
        _loading = true;
        _hits = [];
        _nextCursor = null;
      } else {
        _loadingMore = true;
      }
      _error = null;
      _activeQuery = raw.trim();
    });

    try {
      final page = await _service.search(
        rawQuery: raw,
        type: _type,
        cursor: reset ? null : _nextCursor,
      );

      if (!mounted) return;
      setState(() {
        if (reset) {
          _hits = page.hits;
        } else {
          final seen = _hits.map((h) => h.uid).toSet();
          for (final h in page.hits) {
            if (!seen.contains(h.uid)) _hits.add(h);
          }
        }
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'user_search_error';
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_activeQuery.isEmpty) return;
    await _runSearch(_activeQuery, reset: false);
  }

  void _clearSearch() {
    _debounce?.cancel();
    _debounceHelper.cancel();
    _controller.clear();
    _resetResults();
  }

  Future<void> _openChat(UserSearchHit hit) async {
    if (hit.uid.trim().isEmpty || hit.name.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppTexts.current.get('user_search_profile_unavailable')),
        ),
      );
      return;
    }
    // Premium / nacional: NearbyUsersPage.openChat valida ANTES de criar.
    await NearbyUsersPage.openChat(
      context,
      otherUid: hit.uid,
      otherName: hit.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: _muted),
        title: Text(
          t.get('user_search_title'),
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                t.get('user_search_by_location'),
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _FilterChip(
                    label: t.get('user_search_people'),
                    selected: _type == UserSearchType.name,
                    onTap: () => _onTypeChanged(UserSearchType.name),
                  ),
                  _FilterChip(
                    label: t.get('user_search_city'),
                    selected: _type == UserSearchType.city,
                    onTap: () => _onTypeChanged(UserSearchType.city),
                  ),
                  _FilterChip(
                    label: t.get('user_search_region'),
                    selected: _type == UserSearchType.region,
                    onTap: () => _onTypeChanged(UserSearchType.region),
                  ),
                  _FilterChip(
                    label: t.get('user_search_country'),
                    selected: _type == UserSearchType.country,
                    onTap: () => _onTypeChanged(UserSearchType.country),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: _onQueryChanged,
                      onSubmitted: (v) {
                        _debounce?.cancel();
                        if (UserSearchNormalize.isQueryReady(v)) {
                          _runSearch(v, reset: true);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: t.get(_type.hintKey),
                        hintStyle: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                        prefixIcon: const Icon(Icons.search, color: _muted),
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: t.get('user_search_clear'),
                                onPressed: _clearSearch,
                                icon: const Icon(Icons.clear, color: _muted),
                              ),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: _remdyBlue,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      _debounce?.cancel();
                      final v = _controller.text;
                      if (!UserSearchNormalize.isQueryReady(v)) {
                        setState(
                          () => _showMinCharsHint = v.trim().isNotEmpty,
                        );
                        return;
                      }
                      _runSearch(v, reset: true);
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: _remdyBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      t.get('user_search_action'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            if (_activeQuery.isNotEmpty || _hits.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  t.get(_type.resultsKey),
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            Expanded(child: _buildBody(t, bottomInset)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppTexts t, double bottomInset) {
    if (_showMinCharsHint && _controller.text.trim().isNotEmpty) {
      return _CenteredMessage(t.get('user_search_min_chars'));
    }

    if (_loading && _hits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              t.get('user_search_loading'),
              style: const TextStyle(
                color: _muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.get('user_search_error'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  if (_activeQuery.isNotEmpty) {
                    _runSearch(_activeQuery, reset: true);
                  } else if (UserSearchNormalize.isQueryReady(
                    _controller.text,
                  )) {
                    _runSearch(_controller.text, reset: true);
                  }
                },
                style: TextButton.styleFrom(
                  backgroundColor: _remdyBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  t.get('user_search_retry'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_activeQuery.isEmpty && !_loading) {
      return _CenteredMessage(t.get(_type.hintKey));
    }

    if (!_loading && _hits.isEmpty) {
      return _CenteredMessage(t.get(_type.emptyKey));
    }

    return ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + bottomInset),
      itemCount: _hits.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index >= _hits.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final hit = _hits[index];
        return _UserSearchTile(hit: hit, onTap: () => _openChat(hit));
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? const Color(0xFF313A5F) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF374151),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _UserSearchTile extends StatelessWidget {
  const _UserSearchTile({required this.hit, required this.onTap});

  final UserSearchHit hit;
  final VoidCallback onTap;

  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final locationBits = <String>[];
    if (hit.city != null && hit.city!.isNotEmpty) {
      locationBits.add(hit.city!);
    }
    if (hit.region != null && hit.region!.isNotEmpty) {
      locationBits.add(hit.region!);
    }
    if (hit.country != null && hit.country!.isNotEmpty) {
      locationBits.add(hit.country!);
    } else if (hit.countryCode != null && hit.countryCode!.isNotEmpty) {
      locationBits.add(hit.countryCode!.toUpperCase());
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFFE8ECF4),
                backgroundImage:
                    hit.photoUrl != null && hit.photoUrl!.isNotEmpty
                        ? NetworkImage(hit.photoUrl!)
                        : null,
                child: hit.photoUrl == null || hit.photoUrl!.isEmpty
                    ? Text(
                        hit.name.isNotEmpty ? hit.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: _remdyBlue,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if (locationBits.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        locationBits.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      t.get('user_search_start_chat'),
                      style: const TextStyle(
                        color: _remdyBlue,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}
