import 'package:flutter/material.dart';

import '../features/locais/data/place_repository.dart';
import '../features/locais/locais_feature_flag.dart';
import '../features/locais/locais_strings.dart';
import '../features/locais/models/place_listing.dart';
import '../features/locais/ui/locais_detail_page.dart';
import '../features/locais/ui/place_card.dart';
import '../l10n/app_texts.dart';
import 'home_paged_carousel.dart';
import 'home_section_header.dart';

/// Ordena e corta os locais da Home: destaques (pagos no futuro) na frente,
/// sem repetir local; depois mesmo país, cidade do usuário primeiro,
/// depois abertos agora, no máximo [limit]. Filtragem só no cliente sobre a
/// mesma query pública de Locais (sem índice novo).
List<PlaceListing> selectHomePlaces(
  List<PlaceListing> catalog, {
  required String countryCode,
  String? city,
  required DateTime now,
  int limit = 12,
}) {
  final country = countryCode.trim().toUpperCase();
  final userCity = (city ?? '').trim().toLowerCase();
  final indexed = <int, PlaceListing>{};
  for (var i = 0; i < catalog.length; i++) {
    final p = catalog[i];
    if (country.isNotEmpty && p.address.countryCode.toUpperCase() != country) {
      continue;
    }
    indexed[i] = p;
  }
  final entries = indexed.entries.toList();
  int score(PlaceListing p) {
    var s = 0;
    if (userCity.isNotEmpty &&
        p.address.city.trim().toLowerCase() == userCity) {
      s += 2;
    }
    if (p.isOpenAt(now)) s += 1;
    return s;
  }

  entries.sort((a, b) {
    final promo = b.value.promotionScore.compareTo(a.value.promotionScore);
    if (promo != 0) return promo;
    final d = score(b.value).compareTo(score(a.value));
    return d != 0 ? d : a.key.compareTo(b.key);
  });
  final ordered = homeCarouselOrder<PlaceListing>(
    entries.map((e) => e.value).toList(),
    idOf: (p) => p.id,
    isFeatured: (p) => p.isFeatured,
  );
  return ordered.take(limit.clamp(1, kHomeCarouselMaxItems)).toList();
}

/// Seção "Locais perto de você" na Home. Só existe com Locais ligado e
/// some por inteiro quando não há locais.
class HomePlacesSection extends StatefulWidget {
  const HomePlacesSection({
    super.key,
    required this.countryCode,
    this.city,
    this.onOpenLocaisTab,
    this.repository,
    this.clock,
    this.limit = 12,
  });

  final String countryCode;
  final String? city;
  final VoidCallback? onOpenLocaisTab;
  final PlaceRepository? repository;
  final DateTime Function()? clock;
  final int limit;

  @override
  State<HomePlacesSection> createState() => _HomePlacesSectionState();
}

class _HomePlacesSectionState extends State<HomePlacesSection> {
  PlaceRepository? _repository;
  List<PlaceListing> _catalog = const [];

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (!LocaisFeatureFlag.isEnabled) return;
    _repository = widget.repository ?? createPlaceRepository();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final catalog = await repository.fetchCatalog();
      if (!mounted) return;
      setState(() => _catalog = catalog);
    } catch (_) {
      // Falha: a seção fica escondida, como sem locais.
    }
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

  @override
  Widget build(BuildContext context) {
    if (!LocaisFeatureFlag.isEnabled) return const SizedBox.shrink();
    final now = _now;
    final places = selectHomePlaces(
      _catalog,
      countryCode: widget.countryCode,
      city: widget.city,
      now: now,
      limit: widget.limit,
    );
    if (places.isEmpty) return const SizedBox.shrink();
    final t = AppTexts.current;
    final strings = LocaisStrings.of(context);
    return Padding(
      key: const Key('home_places_section'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeSectionHeader(
            title: t.get('home_places_near_you'),
            seeAllLabel: t.get('home_see_all'),
            onSeeAll: widget.onOpenLocaisTab,
          ),
          const SizedBox(height: 8),
          HomePlacesCarousel(
            places: places,
            strings: strings,
            now: now,
            featuredLabel: t.get('home_featured_badge'),
            onTap: _openDetail,
          ),
        ],
      ),
    );
  }
}

/// Carrossel de locais da Home: 3 por vez, passando de 3 em 3, com o mesmo
/// card vertical de Locais. Destaques ganham o selo "Destaque".
class HomePlacesCarousel extends StatelessWidget {
  const HomePlacesCarousel({
    super.key,
    required this.places,
    required this.strings,
    required this.now,
    required this.featuredLabel,
    required this.onTap,
  });

  final List<PlaceListing> places;
  final LocaisStrings strings;
  final DateTime now;
  final String featuredLabel;
  final ValueChanged<PlaceListing> onTap;

  /// Capa (112) + bloco de texto do card vertical em ~130pt de largura
  /// (nome em 2 linhas, nota e "Aberto agora" em 2 linhas), com a escala
  /// de fonte do usuário.
  static double heightFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return 112 + scaler.scale(168);
  }

  @override
  Widget build(BuildContext context) {
    return HomePagedCarousel(
      key: const Key('home_places_carousel'),
      itemCount: places.length,
      height: heightFor(context),
      gap: 8,
      itemBuilder: (context, i) {
        final place = places[i];
        final card = PlaceCard(
          place: place,
          strings: strings,
          open: place.isOpenAt(now),
          vertical: true,
          onTap: () => onTap(place),
        );
        if (!place.isFeatured) return card;
        return Stack(
          fit: StackFit.expand,
          children: [
            card,
            Positioned(
              top: 8,
              right: 8,
              child: IgnorePointer(
                child: HomeFeaturedBadge(label: featuredLabel),
              ),
            ),
          ],
        );
      },
    );
  }
}
