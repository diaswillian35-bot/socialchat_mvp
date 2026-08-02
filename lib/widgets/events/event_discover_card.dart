import 'package:flutter/material.dart';

import '../../l10n/app_texts.dart';
import '../../models/event_presentation.dart';

/// Card de carrossel — capa, badges, título, local, data.
class EventDiscoverCard extends StatelessWidget {
  const EventDiscoverCard({
    super.key,
    required this.event,
    required this.languageCode,
    required this.onTap,
    this.width = 168,
    this.height = 240,
  });

  final EventPresentation event;
  final String languageCode;
  final VoidCallback onTap;
  final double width;
  final double height;

  static const Color navy = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    final badgeKey = event.statusBadgeKey();
    final badge = badgeKey == null ? null : AppTexts.t(badgeKey);
    final location = event.locationLine(languageCode);
    final imageUrl = event.primaryImageUrl;

    return KeyedSubtree(
      key: ValueKey<String>('event_card_${event.id}'),
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xFFE8ECF4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl.isNotEmpty)
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, __, ___) => const _CoverFallback(),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const _CoverSkeleton();
                        },
                      )
                    else
                      const _CoverFallback(),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x33000000),
                            Color(0x00000000),
                            Color(0xCC1A2038),
                          ],
                          stops: [0, 0.35, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 10,
                      child: Row(
                        children: [
                          if (badge != null && badge.isNotEmpty)
                            _Pill(
                              text: badge,
                              background: _badgeColor(badgeKey!),
                            ),
                          const Spacer(),
                          if (event.category.isNotEmpty)
                            _Pill(
                              text: event.category.toUpperCase(),
                              background: navy.withValues(alpha: 0.85),
                            ),
                        ],
                      ),
                    ),
                    if (event.isConfirmed)
                      Positioned(
                        top: badge == null ? 10 : 40,
                        left: 10,
                        child: _Pill(
                          text: AppTexts.t('events_confirmed_badge'),
                          background: const Color(0xFF16A34A),
                        ),
                      ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            event.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              height: 1.2,
                            ),
                          ),
                          if (location.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.place_outlined,
                                    size: 14, color: Colors.white70),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    location,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined,
                                  size: 13, color: Colors.white70),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  event.shortDateLabel(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Color _badgeColor(String key) {
    switch (key) {
      case 'events_today_badge':
        return const Color(0xFF16A34A);
      case 'events_tomorrow_badge':
        return const Color(0xFFEA580C);
      case 'events_trending_badge':
        return const Color(0xFFDC2626);
      default:
        return navy;
    }
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.background});

  final String text;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF313A5F), Color(0xFF4A5578)],
        ),
      ),
      child: Center(
        child: Icon(Icons.event_rounded, size: 42, color: Colors.white54),
      ),
    );
  }
}

class _CoverSkeleton extends StatelessWidget {
  const _CoverSkeleton();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFE8ECF4),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
