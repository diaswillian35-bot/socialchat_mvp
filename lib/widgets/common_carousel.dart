import 'package:flutter/material.dart';

/// Altura do carrossel "Em comum com você" (antes: cards de 150).
const double commonCarouselHeight = 104;

class CommonCarouselItem {
  const CommonCarouselItem({
    required this.uid,
    required this.name,
    required this.reason,
    required this.avatar,
    this.onTap,
  });
  final String uid;
  final String name;
  final String reason;
  final Widget avatar;
  final VoidCallback? onTap;
}

/// Carrossel horizontal estilo stories: avatar redondo com anel na cor
/// primária, primeiro nome e um motivo curto ("Curte carros").
class CommonCarousel extends StatelessWidget {
  const CommonCarousel({super.key, required this.items});
  final List<CommonCarouselItem> items;

  static String firstName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? name : parts.first;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const ValueKey('country-common-carousel'),
      height: commonCarouselHeight,
      child: ListView.separated(
        key: const PageStorageKey('country-common'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final it = items[i];
          return SizedBox(
            width: 76,
            child: InkWell(
              key: ValueKey('common-${it.uid}'),
              borderRadius: BorderRadius.circular(16),
              onTap: it.onTap,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.primary, width: 2),
                    ),
                    child: it.avatar,
                  ),
                  const SizedBox(height: 4),
                  Text(firstName(it.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                          fontSize: 12)),
                  Text(it.reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: scheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
