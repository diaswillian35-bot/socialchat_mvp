import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../pages/event_detail_page.dart';
import '../services/block_visibility.dart';
import '../widgets/blocked_uids_builder.dart';
import 'home_paged_carousel.dart';
import 'home_section_header.dart';
import '../services/admin_access.dart';

/// Carrossel de eventos na Home.
///
/// Preparado para priorizar patrocinados no futuro (`sponsored` /
/// `isSponsored` / `featured` / `promotionPriority`), sem cobrança nesta versão.
class HomeDiscoverSection extends StatefulWidget {
  const HomeDiscoverSection({
    super.key,
    required this.countryCode,
    this.city,
    this.limit = 20,
    this.onOpenEventsTab,
  });

  final String countryCode;
  final String? city;
  final int limit;

  /// Abre a aba Eventos já montada no [MainShell]. Não usa Navigator.push.
  final VoidCallback? onOpenEventsTab;

  @override
  State<HomeDiscoverSection> createState() => _HomeDiscoverSectionState();
}

class _HomeDiscoverSectionState extends State<HomeDiscoverSection>
    with BlockedUidsListenable {
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visibleDocs => _docs
      .where(
        (d) => !BlockVisibility.hidesEventMap(
          d.data(),
          blocked: blockedUids,
        ),
      )
      .toList();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant HomeDiscoverSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.countryCode != widget.countryCode ||
        oldWidget.city != widget.city ||
        oldWidget.limit != widget.limit) {
      _subscribe();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }

  String _regionKeyFromCity(String city) {
    final c = city.toLowerCase();
    if (c.contains('toronto') ||
        c.contains('north york') ||
        c.contains('york') ||
        c.contains('scarborough') ||
        c.contains('etobicoke') ||
        c.contains('mississauga') ||
        c.contains('brampton')) {
      return 'gta';
    }
    if (c.contains('ottawa')) return 'ottawa';
    return 'default';
  }

  int _promotionScore(Map<String, dynamic> data) =>
      homeEventPromotionScore(data);

  int _locationScore(Map<String, dynamic> data) {
    final userCity = (widget.city ?? '').trim().toLowerCase();
    final userRegion = userCity.isEmpty ? '' : _regionKeyFromCity(userCity);
    final eventCity =
        (data['cityKey'] ?? data['city'] ?? '').toString().trim().toLowerCase();
    final eventRegion =
        (data['regionKey'] ?? '').toString().trim().toLowerCase();

    if (userCity.isNotEmpty && eventCity == userCity) return 30;
    if (userRegion.isNotEmpty &&
        userRegion != 'default' &&
        eventRegion == userRegion) {
      return 20;
    }
    return 10; // mesmo país (já filtrado na query)
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _prepareDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = Timestamp.now();
    final country = widget.countryCode.trim().toLowerCase();

    final upcoming = docs.where((doc) {
      final data = doc.data();
      if (data['isActive'] != true) return false;
      final status =
          (data['status'] ?? 'approved').toString().trim().toLowerCase();
      if (status == 'pending' ||
          status == 'rejected' ||
          status == 'cancelled' ||
          data['deleted'] == true) {
        return false;
      }
      final startAt = data['startAt'];
      if (startAt is! Timestamp || startAt.compareTo(now) <= 0) return false;

      // Conta sem país não vê eventos (admin vê todos); evento sem país
      // não aparece.
      if (country.isEmpty) return AdminAccess.isAdmin;
      final eventCountry = (data['countryCode'] ?? data['country'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return eventCountry.isNotEmpty && eventCountry == country;
    }).toList();

    upcoming.sort((a, b) {
      final aData = a.data();
      final bData = b.data();

      final promo = _promotionScore(bData).compareTo(_promotionScore(aData));
      if (promo != 0) return promo;

      final loc = _locationScore(bData).compareTo(_locationScore(aData));
      if (loc != 0) return loc;

      final aStart = aData['startAt'];
      final bStart = bData['startAt'];
      if (aStart is Timestamp && bStart is Timestamp) {
        return aStart.compareTo(bStart);
      }
      return 0;
    });

    final limit = widget.limit.clamp(1, 20);
    if (upcoming.length <= limit) return upcoming;
    return upcoming.sublist(0, limit);
  }

  void _subscribe() {
    _sub?.cancel();

    final country = widget.countryCode.trim().toLowerCase();
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('events')
        .where('isActive', isEqualTo: true)
        .where('startAt', isGreaterThan: Timestamp.now())
        .orderBy('startAt')
        .limit(50);

    if (country.isNotEmpty) {
      query = FirebaseFirestore.instance
          .collection('events')
          .where('isActive', isEqualTo: true)
          .where('countryCode', isEqualTo: country)
          .where('startAt', isGreaterThan: Timestamp.now())
          .orderBy('startAt')
          .limit(50);
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _hasError = false;
      });
    }

    _sub = query.snapshots().listen(
      (snap) {
        if (!mounted) return;
        final prepared = _prepareDocs(snap.docs);
        _applyDocs(prepared);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _hasError = true;
          _docs = const [];
        });
      },
    );
  }

  void _applyDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    setState(() {
      _docs = docs;
      _loading = false;
      _hasError = false;
    });
  }

  String _resolveImageUrl(Map<String, dynamic> data) {
    final cover = (data['coverUrl'] ?? '').toString().trim();
    if (cover.isNotEmpty) return cover;

    final rawPhotos = data['photoUrls'];
    if (rawPhotos is List) {
      for (final e in rawPhotos) {
        final url = e.toString().trim();
        if (url.isNotEmpty) return url;
      }
    }
    for (final key in ['coverImageUrl', 'imageUrl']) {
      final url = (data[key] ?? '').toString().trim();
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  String _fmtDate(Timestamp? ts) {
    if (ts == null) return AppTexts.t('events_no_date');
    final d = ts.toDate();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  String _eventBadge(Timestamp? ts) {
    if (ts == null) return '';
    final now = DateTime.now();
    final date = ts.toDate();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    final diff = eventDay.difference(today).inDays;
    if (diff == 0) return AppTexts.t('events_today_badge');
    if (diff == 1) return AppTexts.t('events_tomorrow_badge');
    return '';
  }

  void _openEvent(String eventId, Map<String, dynamic> data) {
    if (BlockVisibility.hidesEventMap(data, blocked: blockedUids)) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailPage(eventId: eventId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;

    if (_loading && _visibleDocs.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_hasError || _visibleDocs.isEmpty) {
      // 0 eventos: ocultar seção por completo (sem espaço vazio).
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: t.get('home_discover'),
          seeAllLabel: t.get('home_see_all'),
          onSeeAll: widget.onOpenEventsTab,
        ),
        const SizedBox(height: 8),
        _pagedCarousel(context),
      ],
    );
  }

  /// 3 eventos por vez, passando de 3 em 3. Destaques (pagos no futuro)
  /// vêm na frente com o selo "Destaque"; sem cobrança nesta versão.
  Widget _pagedCarousel(BuildContext context) {
    final docs = homeCarouselOrder<QueryDocumentSnapshot<Map<String, dynamic>>>(
      _visibleDocs,
      idOf: (d) => d.id,
      ownerOf: (d) => homeEventOwnerKey(d.data()),
      isFeatured: (d) => homeEventPromotionScore(d.data()) > 0,
    ).take(kHomeCarouselMaxItems).toList();
    final featuredLabel = AppTexts.t('home_featured_badge');
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final cardWidth = (constraints.maxWidth - gap * 2) / 3;
        final height = (cardWidth * 1.58).clamp(168.0, 210.0);
        return HomePagedCarousel(
          key: const Key('home_discover_carousel'),
          itemCount: docs.length,
          height: height,
          gap: gap,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();
            return HomeEventCard(
              data: data,
              compact: true,
              wide: false,
              featuredLabel:
                  homeEventPromotionScore(data) > 0 ? featuredLabel : null,
              resolveImageUrl: _resolveImageUrl,
              fmtDate: _fmtDate,
              eventBadge: _eventBadge,
              onTap: () => _openEvent(doc.id, data),
            );
          },
        );
      },
    );
  }
}

/// Dono do evento, para não repetir o mesmo organizador na mesma página.
String homeEventOwnerKey(Map<String, dynamic> data) {
  for (final k in [
    'businessId',
    'organizerId',
    'createdBy',
    'ownerId',
    'uid'
  ]) {
    final v = (data[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return '';
}

/// Score de monetização futura (patrocinado > featured > priority).
int homeEventPromotionScore(Map<String, dynamic> data) {
  if (data['isSponsored'] == true || data['sponsored'] == true) {
    return 300;
  }
  if (data['featured'] == true ||
      data['isBoosted'] == true ||
      data['boosted'] == true) {
    return 200;
  }
  final raw = data['promotionPriority'];
  if (raw is num && raw > 0) {
    return 100 + raw.toInt().clamp(0, 99);
  }
  return 0;
}

/// Card de evento da Home (mesmo visual de antes).
class HomeEventCard extends StatelessWidget {
  const HomeEventCard({
    super.key,
    required this.data,
    required this.resolveImageUrl,
    required this.fmtDate,
    required this.eventBadge,
    required this.onTap,
    required this.compact,
    required this.wide,
    this.featuredLabel,
  });

  final Map<String, dynamic> data;
  final String? featuredLabel;
  final String Function(Map<String, dynamic>) resolveImageUrl;
  final String Function(Timestamp?) fmtDate;
  final String Function(Timestamp?) eventBadge;
  final VoidCallback onTap;
  final bool compact;
  final bool wide;

  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _logoBlue = Color(0xFF264E9A);

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final title = (data['title'] ?? 'Evento').toString();
    final city = (data['city'] ?? '').toString();
    final category =
        (data['category'] ?? t.get('events_default_category')).toString();
    final startAt =
        data['startAt'] is Timestamp ? data['startAt'] as Timestamp : null;
    final imageUrl = resolveImageUrl(data);
    final badge = eventBadge(startAt);
    final dateText = fmtDate(startAt);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(13),
                      ),
                      child: ColoredBox(
                        color: const Color(0xFFF1F5F9),
                        child: imageUrl.isNotEmpty
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (_, __, ___) => _placeholder(),
                              )
                            : _placeholder(),
                      ),
                    ),
                    if (badge.isNotEmpty)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: badge == t.get('events_today_badge')
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFF97316),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    if (featuredLabel != null)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: HomeFeaturedBadge(label: featuredLabel!),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  wide ? 10 : 7,
                  6,
                  wide ? 10 : 7,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _text,
                        fontSize: wide ? 13 : 11,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                      ),
                    ),
                    if (category.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _logoBlue,
                          fontSize: wide ? 11 : 10,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      dateText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _muted,
                        fontSize: wide ? 11 : 10,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                    if (city.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _muted,
                          fontSize: wide ? 11 : 10,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFEFF2F7),
      alignment: Alignment.center,
      child: const Icon(
        Icons.event_rounded,
        color: Color(0xFF94A3B8),
        size: 28,
      ),
    );
  }
}
