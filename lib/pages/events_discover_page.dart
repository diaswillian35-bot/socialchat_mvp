import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../models/event_presentation.dart';
import '../services/event_deep_link_service.dart';
import '../services/events_discover_feed_logic.dart';
import '../services/events_discover_feed_service.dart';
import '../widgets/events/event_discover_card.dart';
import '../widgets/events/event_section_row.dart';
import '../widgets/remdy_logo.dart';
import 'event_detail_page.dart';
import 'my_events_page.dart';

/// Nova experiência de lista de Eventos (carrosséis + fundo claro Remdy).
class EventsDiscoverPage extends StatefulWidget {
  const EventsDiscoverPage({super.key, this.openEventId});

  final String? openEventId;

  @override
  State<EventsDiscoverPage> createState() => _EventsDiscoverPageState();
}

class _EventsDiscoverPageState extends State<EventsDiscoverPage> {
  final _feed = EventsDiscoverFeedService();

  EventsDiscoverFeedResult? _result;
  Object? _error;
  bool _loading = true;
  bool _openedDeepEvent = false;

  static const Color _bg = Color(0xFFF7F8FC);
  static const Color _navy = Color(0xFF313A5F);
  static const Color _muted = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = (widget.openEventId ?? '').trim();
      if (id.isEmpty || _openedDeepEvent || !mounted) return;
      _openedDeepEvent = true;
      EventDeepLinkService.openEventById(context, eventId: id);
    });
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _feed.load();
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _openDetail(EventPresentation event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailPage(eventId: event.id),
      ),
    );
  }

  void _openSeeAll(String title, List<EventPresentation> events) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EventsSeeAllPage(
          title: title,
          events: events,
          languageCode: Localizations.localeOf(context).languageCode,
          onTap: _openDetail,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: _navy,
          onRefresh: _reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: RemdyLogo(),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MyEventsPage(),
                            ),
                          );
                        },
                        child: Text(
                          AppTexts.t('events_my_events'),
                          style: const TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppTexts.t('events_title'),
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppTexts.t('events_subtitle'),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading && _result == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _result == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorState(onRetry: _reload),
                )
              else ...[
                ..._sectionSlivers(lang),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sectionSlivers(String lang) {
    final sections = _result?.sections;
    if (sections == null || sections.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                AppTexts.t('events_empty_country'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ];
    }

    final widgets = <Widget>[];

    void addSection(String titleKey, List<EventPresentation> items) {
      if (items.isEmpty) return;
      final title = AppTexts.t(titleKey);
      widgets.add(
        SliverToBoxAdapter(
          child: EventSectionRow(
            title: title,
            events: items,
            languageCode: lang,
            onSeeAll: () => _openSeeAll(title, items),
            onEventTap: _openDetail,
          ),
        ),
      );
    }

    addSection('events_section_featured', sections.featured);
    addSection('events_section_near_you', sections.nearby);
    addSection('events_section_today', sections.today);
    addSection('events_section_upcoming', sections.upcoming);

    final catKeys = sections.categories.keys.toList()..sort();
    for (final key in catKeys) {
      final items = sections.categories[key]!;
      if (items.isEmpty) continue;
      final title = AppTexts.t(EventsDiscoverFeedLogic.categoryL10nKey(key));
      widgets.add(
        SliverToBoxAdapter(
          child: EventSectionRow(
            title: title,
            events: items,
            languageCode: lang,
            onSeeAll: () => _openSeeAll(title, items),
            onEventTap: _openDetail,
          ),
        ),
      );
    }

    if (widgets.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              AppTexts.t('events_empty_country'),
              style: const TextStyle(
                color: _muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ];
    }
    return widgets;
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppTexts.t('events_load_error'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF313A5F),
              ),
              child: Text(AppTexts.t('events_retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventsSeeAllPage extends StatelessWidget {
  const _EventsSeeAllPage({
    required this.title,
    required this.events,
    required this.languageCode,
    required this.onTap,
  });

  final String title;
  final List<EventPresentation> events;
  final String languageCode;
  final void Function(EventPresentation) onTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF313A5F),
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF313A5F)),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemCount: events.length,
        itemBuilder: (context, i) {
          final e = events[i];
          return EventDiscoverCard(
            event: e,
            languageCode: languageCode,
            width: double.infinity,
            height: double.infinity,
            onTap: () => onTap(e),
          );
        },
      ),
    );
  }
}
