import 'package:flutter/material.dart';

import '../locais_strings.dart';
import '../models/place_listing.dart';
import 'locais_layout.dart';

IconData placeCategoryIcon(PlaceCategory category) {
  switch (category) {
    case PlaceCategory.restaurant:
      return Icons.restaurant_rounded;
    case PlaceCategory.bar:
      return Icons.local_bar_rounded;
    case PlaceCategory.cafe:
      return Icons.coffee_rounded;
    case PlaceCategory.hotel:
      return Icons.hotel_rounded;
    case PlaceCategory.pousada:
      return Icons.cottage_rounded;
    case PlaceCategory.nightclub:
      return Icons.nightlife_rounded;
  }
}

class PlaceCover extends StatelessWidget {
  const PlaceCover({
    super.key,
    required this.photo,
    required this.category,
    this.width,
    this.height,
  });

  final PlacePhoto photo;
  final PlaceCategory category;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: photo.alt,
      image: true,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(photo.color),
                Color(photo.color).withValues(alpha: 0.72),
              ],
            ),
          ),
          child: Center(
            child: Icon(
              placeCategoryIcon(category),
              color: Colors.white,
              size: height != null && height! < 80 ? 28 : 36,
            ),
          ),
        ),
      ),
    );
  }
}

class PlaceCard extends StatelessWidget {
  const PlaceCard({
    super.key,
    required this.place,
    required this.strings,
    required this.open,
    required this.onTap,
    this.vertical = false,
  });

  final PlaceListing place;
  final LocaisStrings strings;
  final bool open;
  final VoidCallback onTap;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final label = strings.cardLabel(
      name: place.name,
      category: strings.categoryName(place.category),
      city: place.address.city,
      rating: place.rating,
      count: place.ratingCount,
      open: open,
    );
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: LocaisColors.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: Key('place_card_${place.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: LocaisColors.border),
            ),
            child: vertical ? _vertical() : _horizontal(),
          ),
        ),
      ),
    );
  }

  Widget _horizontal() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 112),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(17),
            ),
            child: PlaceCover(
              photo: place.cover,
              category: place.category,
              width: 104,
              height: 112,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: _textBlock(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vertical() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
          child: PlaceCover(
            photo: place.cover,
            category: place.category,
            height: 112,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: _textBlock(),
        ),
      ],
    );
  }

  Widget _textBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.categoryName(place.category).toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: LocaisColors.logoBlue,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          place.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: LocaisColors.text,
            fontSize: 16,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${place.address.district} · ${place.address.city}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: LocaisColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _RatingLine(
              label: strings.ratingLine(place.rating, place.ratingCount),
            ),
            _StatusPill(
              open: open,
              label: open ? strings.openNow : strings.closed,
            ),
          ],
        ),
      ],
    );
  }
}

class _RatingLine extends StatelessWidget {
  const _RatingLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF5B301)),
        const SizedBox(width: 2),
        Text(
          label,
          style: const TextStyle(
            color: LocaisColors.text,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.open, required this.label});

  final bool open;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = open ? LocaisColors.open : LocaisColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
