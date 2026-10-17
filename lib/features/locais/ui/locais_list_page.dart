import 'package:flutter/material.dart';

import '../../../widgets/remdy_logo.dart';
import '../data/place_repository.dart';
import '../locais_feature_flag.dart';
import '../locais_strings.dart';
import '../logic/place_query.dart';
import '../models/place_listing.dart';
import 'locais_layout.dart';
import 'locais_state_views.dart';
import 'place_card.dart';
import 'locais_detail_page.dart';

/// Lista e mapa de Locais. Com a flag desligada não desenha conteúdo.
class LocaisListPage extends StatefulWidget {
  const LocaisListPage({super.key, this.repository, this.clock});

  final PlaceRepository? repository;
  final DateTime Function()? clock;

  @override
  State<LocaisListPage> createState() => _LocaisListPageState();
}

class _LocaisListPageState extends State<LocaisListPage> {
  final PlaceQueryEngine _engine = const PlaceQueryEngine();
  final TextEditingController _search = TextEditingController();

  PlaceRepository? _repository;
  List<PlaceListing> _catalog = const [];
  PlaceQuery _query = const PlaceQuery();
  bool _loading = true;
  bool _failed = false;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (!LocaisFeatureFlag.isEnabled) return;
    _repository = widget.repository ?? createPlaceRepository();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final catalog = await repository.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  List<PlaceListing> get _visible {
    return _engine.apply(source: _catalog, query: _query, now: _now);
  }

  void _openDetail(PlaceListing place) {
    final repository = _repository;
    if (repository == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocaisDetailPage(
          placeId: place.id,
          repository: repository,
          clock: widget.clock,
        ),
      ),
    );
  }

  Future<void> _openFilters(LocaisStrings strings) async {
    final next = await showModalBottomSheet<PlaceQuery>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => _FilterSheet(initial: _query, strings: strings),
    );
    if (!mounted || next == null) return;
    setState(() => _query = next);
  }

  @override
  Widget build(BuildContext context) {
    if (!LocaisFeatureFlag.isEnabled) {
      return const SizedBox.shrink(key: Key('locais_disabled'));
    }
    final strings = LocaisStrings.of(context);
    final visible = _visible;
    return Scaffold(
      backgroundColor: LocaisColors.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return _results(strings, visible, constraints.maxWidth);
          },
        ),
      ),
    );
  }

  Widget _results(
    LocaisStrings strings,
    List<PlaceListing> visible,
    double width,
  ) {
    return CustomScrollView(
      key: const Key('locais_scroll'),
      slivers: [
        SliverToBoxAdapter(child: _header(strings)),
        SliverToBoxAdapter(child: _searchField(strings)),
        SliverToBoxAdapter(child: _categories(strings)),
        SliverToBoxAdapter(child: _toolbar(strings)),
        if (_loading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: LocaisLoading(label: strings.loading),
          )
        else if (_failed)
          SliverFillRemaining(
            hasScrollBody: false,
            child: LocaisError(
              title: strings.errorTitle,
              retryLabel: strings.retry,
              onRetry: _load,
            ),
          )
        else if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: LocaisEmpty(
              title: strings.emptyTitle,
              body: strings.emptyBody,
            ),
          )
        else
          _placeSliver(strings, visible, width),
      ],
    );
  }

  Widget _header(LocaisStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: RemdyLogo(height: 48)),
          const SizedBox(height: 8),
          Text(
            strings.title,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w900,
              color: LocaisColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            strings.subtitle,
            style: const TextStyle(
              fontSize: 14,
              height: 1.3,
              color: LocaisColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(LocaisStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Semantics(
        label: strings.searchLabel,
        textField: true,
        child: TextField(
          textCapitalization: TextCapitalization.none,
          key: const Key('locais_search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: strings.searchHint,
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: LocaisColors.navy,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: LocaisColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: LocaisColors.border),
            ),
          ),
          onChanged: (value) => setState(() {
            _query = _query.copyWith(search: value);
          }),
        ),
      ),
    );
  }

  Widget _categories(LocaisStrings strings) {
    final categories = <PlaceCategory?>[null, ...PlaceCategory.values];
    return Padding(
      key: const Key('locais_categories'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final category in categories) _categoryChip(strings, category),
        ],
      ),
    );
  }

  Widget _categoryChip(LocaisStrings strings, PlaceCategory? category) {
    final selected = _query.category == category;
    final keyName = category?.name ?? 'all';
    return FilterChip(
      key: Key('locais_category_$keyName'),
      label: Text(
        category == null ? strings.categoryAll : strings.categoryName(category),
      ),
      selected: selected,
      showCheckmark: false,
      selectedColor: LocaisColors.navy,
      labelStyle: TextStyle(
        color: selected ? Colors.white : LocaisColors.navy,
        fontWeight: FontWeight.w700,
      ),
      side: const BorderSide(color: LocaisColors.border),
      onSelected: (_) {
        setState(() {
          _query = _query.copyWith(
            category: category,
            clearCategory: category == null,
          );
        });
      },
    );
  }

  Widget _toolbar(LocaisStrings strings) {
    final filtering = _query.openNow ||
        _query.wheelchairEntrance ||
        _query.minRating != null ||
        _query.search.trim().isNotEmpty ||
        _query.category != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            key: const Key('locais_filter_button'),
            style: OutlinedButton.styleFrom(
              foregroundColor: LocaisColors.navy,
              minimumSize: const Size(48, 44),
              side: const BorderSide(color: LocaisColors.border),
            ),
            onPressed: () => _openFilters(strings),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text(strings.filter),
          ),
          if (filtering)
            TextButton(
              key: const Key('locais_clear_filters'),
              onPressed: () {
                _search.clear();
                setState(() => _query = const PlaceQuery());
              },
              child: Text(strings.clearFilters),
            ),
        ],
      ),
    );
  }

  Widget _placeSliver(
    LocaisStrings strings,
    List<PlaceListing> visible,
    double width,
  ) {
    final columns = LocaisLayout.columnsForWidth(
      width >= 900 ? width * 0.6 : width,
    );
    if (columns == 1) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        sliver: SliverList.separated(
          itemCount: visible.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final place = visible[index];
            return PlaceCard(
              place: place,
              strings: strings,
              open: place.isOpenAt(_now),
              onTap: () => _openDetail(place),
            );
          },
        ),
      );
    }
    final rows = (visible.length / columns).ceil();
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      sliver: SliverList.builder(
        itemCount: rows,
        itemBuilder: (context, row) {
          final start = row * columns;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) const SizedBox(width: 12),
                  Expanded(
                    child: start + column < visible.length
                        ? PlaceCard(
                            place: visible[start + column],
                            strings: strings,
                            open: visible[start + column].isOpenAt(_now),
                            vertical: true,
                            onTap: () => _openDetail(visible[start + column]),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.strings});

  final PlaceQuery initial;
  final LocaisStrings strings;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late bool _openNow = widget.initial.openNow;
  late bool _wheelchair = widget.initial.wheelchairEntrance;
  late double? _minRating = widget.initial.minRating;

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: LocaisColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text(
              strings.filterTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: LocaisColors.text,
              ),
            ),
            SwitchListTile(
              key: const Key('locais_filter_open_now'),
              contentPadding: EdgeInsets.zero,
              title: Text(strings.openNowFilter),
              value: _openNow,
              activeThumbColor: LocaisColors.navy,
              onChanged: (value) => setState(() => _openNow = value),
            ),
            SwitchListTile(
              key: const Key('locais_filter_wheelchair'),
              contentPadding: EdgeInsets.zero,
              title: Text(strings.wheelchair),
              value: _wheelchair,
              activeThumbColor: LocaisColors.navy,
              onChanged: (value) => setState(() => _wheelchair = value),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('locais_filter_rating_any'),
                  label: Text(strings.minRatingAny),
                  selected: _minRating == null,
                  onSelected: (_) => setState(() => _minRating = null),
                ),
                ChoiceChip(
                  key: const Key('locais_filter_rating_4'),
                  label: Text(strings.minRating4),
                  selected: _minRating == 4,
                  onSelected: (_) => setState(() => _minRating = 4),
                ),
                ChoiceChip(
                  key: const Key('locais_filter_rating_45'),
                  label: Text(strings.minRating45),
                  selected: _minRating == 4.5,
                  onSelected: (_) => setState(() => _minRating = 4.5),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('locais_filter_apply'),
                style: FilledButton.styleFrom(
                  backgroundColor: LocaisColors.navy,
                  minimumSize: const Size(48, 48),
                ),
                onPressed: () {
                  Navigator.of(context).pop(
                    widget.initial.copyWith(
                      openNow: _openNow,
                      wheelchairEntrance: _wheelchair,
                      minRating: _minRating,
                      clearMinRating: _minRating == null,
                    ),
                  );
                },
                child: Text(strings.apply),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
