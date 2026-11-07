// Prévia local dos carrosséis da Home (não entra no app; só `flutter run -t`).
// Dados de exemplo + o evento "Teste" e a capa do John Burger reais.
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:socialchat_mvp/features/locais/data/demo_places.dart';
import 'package:socialchat_mvp/features/locais/locais_strings.dart';
import 'package:socialchat_mvp/features/locais/models/place_listing.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/widgets/home_discover_section.dart';
import 'package:socialchat_mvp/widgets/home_paged_carousel.dart';
import 'package:socialchat_mvp/widgets/home_places_section.dart';
import 'package:socialchat_mvp/widgets/home_section_header.dart';

const _lang = String.fromEnvironment('PREVIEW_LANG', defaultValue: 'pt-BR');
const _page = int.fromEnvironment('PREVIEW_PAGE', defaultValue: 0);

const _jbCover =
    'https://firebasestorage.googleapis.com/v0/b/socialchatmvp.firebasestorage.app/o/places%2FhPGFEU4iQbDJXItOwQhV%2Fphotos%2F249b720ad29516bb5e39bce58660f152.jpg?alt=media&token=670d4b83-8eda-4539-a039-e1ab33aa2444';
const _testeCover =
    'https://firebasestorage.googleapis.com/v0/b/socialchatmvp.firebasestorage.app/o/events%2F2UrrzsLSexQT2II2l69b%2Fphotos%2F1794022652770_0.jpg?alt=media&token=e07bb5bd-405a-48b3-bfa8-16556a4d13d1';

PlaceListing _as(PlaceListing p,
        {String? id,
        String? name,
        String? url,
        bool? deliveryOnly,
        int promotionScore = 0}) =>
    PlaceListing(
      id: id ?? p.id,
      slug: p.slug,
      name: name ?? p.name,
      category: p.category,
      description: p.description,
      photos: url == null
          ? p.photos
          : [PlacePhoto(id: 'c', alt: name ?? p.name, color: 0xFF313A5F, url: url)],
      rating: p.rating,
      ratingCount: p.ratingCount,
      address: p.address,
      contact: p.contact,
      hours: p.hours,
      accessibility: p.accessibility,
      reviews: p.reviews,
      upcomingEvents: p.upcomingEvents,
      deliveryOnly: deliveryOnly ?? p.deliveryOnly,
      timeZone: p.timeZone,
      promotionScore: promotionScore,
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final parts = _lang.split('-');
  final locale = Locale(parts[0], parts.length > 1 ? parts[1] : null);
  await AppTexts.load(locale);
  LocaisStrings.debugLocale = locale;
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _PreviewHome(),
    );
  }
}

class _PreviewHome extends StatefulWidget {
  const _PreviewHome();

  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  final _now = DateTime.now();

  Map<String, dynamic> _event(String id, String title, String cat,
          DateTime when, String city,
          {String? cover, bool featured = false, String owner = ''}) =>
      {
        'id': id,
        'title': title,
        'category': cat,
        'startAt': Timestamp.fromDate(when),
        'city': city,
        if (cover != null) 'coverUrl': cover,
        if (featured) 'featured': true,
        'createdBy': owner.isEmpty ? id : owner,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final strings = LocaisStrings.of(context);
    final d = DateTime(_now.year, _now.month, _now.day, 20);
    final events = homeCarouselOrder<Map<String, dynamic>>(
      [
        _event('teste', 'Teste', 'Esportes', DateTime(2026, 11, 9, 9),
            'Toronto', cover: _testeCover),
        _event('e1', 'Noite de Forró no Centro', 'Música',
            d.add(const Duration(days: 1)), 'Toronto', featured: true),
        _event('e2', 'Feira Brasileira de Artesanato', 'Cultura', d,
            'Mississauga'),
        _event('e3', 'Pelada de domingo', 'Esportes',
            d.add(const Duration(days: 3)), 'Toronto'),
        _event('e4', 'Encontro de Networking', 'Networking',
            d.add(const Duration(days: 5)), 'Toronto'),
        _event('e5', 'Cinema ao ar livre', 'Cultura',
            d.add(const Duration(days: 8)), 'Toronto'),
      ],
      idOf: (e) => e['id'] as String,
      ownerOf: (e) => e['createdBy'] as String,
      isFeatured: (e) => homeEventPromotionScore(e) > 0,
    );
    final demo = DemoPlaces.all;
    final places = homeCarouselOrder<PlaceListing>(
      [
        _as(demo[1], id: 'destaque', promotionScore: 200),
        _as(demo[0],
            id: 'john_burger',
            name: 'John Burger',
            url: _jbCover,
            deliveryOnly: true),
        ...demo.skip(2).take(5),
      ],
      idOf: (p) => p.id,
      isFeatured: (p) => p.isFeatured,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 120),
              HomeSectionHeader(
                title: t.get('home_discover'),
                seeAllLabel: t.get('home_see_all'),
                onSeeAll: () {},
              ),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (context, c) {
                final cardWidth = (c.maxWidth - 16) / 3;
                return _Jump(
                  child: HomePagedCarousel(
                    itemCount: events.length,
                    height: (cardWidth * 1.58).clamp(168.0, 210.0),
                    itemBuilder: (context, i) => HomeEventCard(
                      data: events[i],
                      compact: true,
                      wide: false,
                      featuredLabel: homeEventPromotionScore(events[i]) > 0
                          ? t.get('home_featured_badge')
                          : null,
                      resolveImageUrl: (m) => (m['coverUrl'] ?? '') as String,
                      fmtDate: (ts) {
                        final x = ts!.toDate();
                        String two(int n) => n.toString().padLeft(2, '0');
                        return '${two(x.day)}/${two(x.month)}/${x.year}';
                      },
                      eventBadge: (ts) {
                        final x = ts!.toDate();
                        final diff = DateTime(x.year, x.month, x.day)
                            .difference(
                                DateTime(_now.year, _now.month, _now.day))
                            .inDays;
                        if (diff == 0) return t.get('events_today_badge');
                        if (diff == 1) return t.get('events_tomorrow_badge');
                        return '';
                      },
                      onTap: () {},
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              HomeSectionHeader(
                title: t.get('home_places_near_you'),
                seeAllLabel: t.get('home_see_all'),
                onSeeAll: () {},
              ),
              const SizedBox(height: 8),
              _Jump(
                child: HomePlacesCarousel(
                  places: places,
                  strings: strings,
                  now: DateTime(_now.year, _now.month, _now.day, 13),
                  featuredLabel: t.get('home_featured_badge'),
                  onTap: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vai direto para a página PREVIEW_PAGE (para os prints da 2ª página).
class _Jump extends StatefulWidget {
  const _Jump({required this.child});
  final Widget child;
  @override
  State<_Jump> createState() => _JumpState();
}

class _JumpState extends State<_Jump> {
  @override
  void initState() {
    super.initState();
    if (_page > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        void visit(Element e) {
          if (e.widget is PageView) {
            (e.widget as PageView).controller?.jumpToPage(_page);
            return;
          }
          e.visitChildElements(visit);
        }

        (context as Element).visitChildElements(visit);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
