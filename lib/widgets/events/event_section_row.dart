import 'package:flutter/material.dart';

import '../../l10n/app_texts.dart';
import '../../models/event_presentation.dart';
import 'event_discover_card.dart';

class EventSectionRow extends StatelessWidget {
  const EventSectionRow({
    super.key,
    required this.title,
    required this.events,
    required this.languageCode,
    required this.onSeeAll,
    required this.onEventTap,
  });

  final String title;
  final List<EventPresentation> events;
  final String languageCode;
  final VoidCallback onSeeAll;
  final void Function(EventPresentation event) onEventTap;

  static const Color navy = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: onSeeAll,
                child: Text(
                  AppTexts.t('events_see_all'),
                  style: const TextStyle(
                    color: navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 248,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: events.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final e = events[index];
              return EventDiscoverCard(
                event: e,
                languageCode: languageCode,
                onTap: () => onEventTap(e),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
