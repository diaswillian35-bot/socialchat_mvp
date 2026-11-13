import 'package:flutter/material.dart';

import 'place_photo_viewer.dart';

import '../locais_strings.dart';
import '../models/place_listing.dart';
import 'locais_layout.dart';
import 'place_discount_badge.dart';

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
    final url = placeSafeImageUrl(photo.url);
    final placeholder = DecoratedBox(
      key: const Key('place_cover_placeholder'),
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
    );
    return Semantics(
      label: photo.alt,
      image: true,
      child: SizedBox(
        width: width,
        height: height,
        // Com foto: fundo branco desde o 1º frame (logo PNG transparente) e,
        // ao trocar de foto, a anterior fica até a nova carregar
        // (gaplessPlayback). O placeholder azul só aparece sem foto ou em erro.
        child: url == null
            ? placeholder
            : ColoredBox(
                key: const Key('place_cover_loaded'),
                color: Colors.white,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final dpr =
                        MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
                    final w = box.maxWidth.isFinite ? box.maxWidth : 600.0;
                    final h = box.maxHeight.isFinite ? box.maxHeight : w;
                    return _AdaptiveCoverImage(
                      url: url,
                      boxAspect: h > 0 ? w / h : 1,
                      cacheWidth: (w * dpr).clamp(64, 1600).round(),
                      placeholder: placeholder,
                    );
                  },
                ),
              ),
      ),
    );
  }
}

/// Logo quadrada/retrato (ex.: logo redonda) numa capa mais larga é
/// mostrada inteira (contain) sobre o fundo branco, sem cortar o topo.
/// Fotos largas continuam preenchendo a capa (cover).
BoxFit placeCoverFit({required double imageAspect, required double boxAspect}) {
  if (imageAspect <= 0 || boxAspect <= 0) return BoxFit.cover;
  final squareOrPortrait = imageAspect <= 1.1;
  final boxWider = boxAspect > imageAspect * 1.05;
  return squareOrPortrait && boxWider ? BoxFit.contain : BoxFit.cover;
}

class _AdaptiveCoverImage extends StatefulWidget {
  const _AdaptiveCoverImage({
    required this.url,
    required this.boxAspect,
    required this.cacheWidth,
    required this.placeholder,
  });

  final String url;
  final double boxAspect;
  final int cacheWidth;
  final Widget placeholder;

  @override
  State<_AdaptiveCoverImage> createState() => _AdaptiveCoverImageState();
}

class _AdaptiveCoverImageState extends State<_AdaptiveCoverImage> {
  double? _imageAspect;

  @override
  void didUpdateWidget(covariant _AdaptiveCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _imageAspect = null;
      _reading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final aspect = _imageAspect;
    return Image.network(
      widget.url,
      key: const Key('place_cover_image'),
      fit: aspect == null
          ? BoxFit.cover
          : placeCoverFit(imageAspect: aspect, boxAspect: widget.boxAspect),
      width: double.infinity,
      height: double.infinity,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, _) {
        if (frame != null) _readAspect(context);
        return child;
      },
      errorBuilder: (_, __, ___) => widget.placeholder,
    );
  }

  bool _reading = false;

  void _readAspect(BuildContext context) {
    if (_imageAspect != null || _reading) return;
    _reading = true;
    // Fora do build: o listener pode disparar na hora (imagem em cache).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _resolveAspect();
    });
  }

  void _resolveAspect() {
    final provider = ResizeImage.resizeIfNeeded(
      widget.cacheWidth,
      null,
      NetworkImage(widget.url),
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      _reading = false;
      final img = info.image;
      if (!mounted || img.height == 0) return;
      final a = img.width / img.height;
      if (a != _imageAspect) setState(() => _imageAspect = a);
    }, onError: (_, __) {
      stream.removeListener(listener);
      _reading = false;
    });
    stream.addListener(listener);
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
    this.onDiscountTap,
  });

  final PlaceListing place;
  final LocaisStrings strings;
  final bool open;
  final VoidCallback onTap;
  final bool vertical;
  final VoidCallback? onDiscountTap;

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

  Widget _coverWithBadge({double? width, double? height}) {
    final cover = PlaceCover(
      photo: place.cover,
      category: place.category,
      width: width,
      height: height,
    );
    final discount = place.discount;
    if (discount == null || !discount.isActiveAt(DateTime.now())) {
      return cover;
    }
    return Stack(
      children: [
        cover,
        Positioned(
          top: 8,
          left: 8,
          child: PlaceDiscountBadge(
            discount: discount,
            onTap: onDiscountTap,
          ),
        ),
      ],
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
            child: _coverWithBadge(width: 104, height: 112),
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
          child: _coverWithBadge(height: 112),
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
          [place.address.district, place.address.city]
              .where((part) => part.trim().isNotEmpty)
              .join(' · '),
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
            if (!place.hoursUnknown)
              _StatusPill(
                open: open,
                label: open ? strings.openNow : strings.closed,
              ),
            if (place.deliveryOnly)
              _StatusPill(
                key: const Key('place_card_delivery_badge'),
                open: true,
                label: strings.deliveryBadge,
                color: LocaisColors.logoBlue,
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
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: LocaisColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    super.key,
    required this.open,
    required this.label,
    this.color,
  });

  final bool open;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? (open ? LocaisColors.open : LocaisColors.muted);
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
