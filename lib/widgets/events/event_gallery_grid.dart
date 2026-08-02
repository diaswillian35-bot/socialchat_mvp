import 'package:flutter/material.dart';

import '../../l10n/app_texts.dart';

/// Grade da aba Galeria — 1 a 5 fotos, sempre [BoxFit.contain], sem células vazias.
class EventGalleryGrid extends StatelessWidget {
  const EventGalleryGrid({
    super.key,
    required this.urls,
    this.onPhotoTap,
    this.selectedIndex = 0,
  });

  static const Color cellBg = Color(0xFFF8F9FC);
  static const Color navySoft = Color(0xFFF3F5FA);
  static const Color selectedBorder = Color(0xFF313A5F);
  static const double radius = 14;

  final List<String> urls;
  final ValueChanged<int>? onPhotoTap;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppTexts.t('events_tab_gallery'),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: Color(0xFF313A5F),
          ),
        ),
        const SizedBox(height: 10),
        if (urls.length == 1)
          _GalleryCell(
            url: urls.first,
            index: 0,
            total: 1,
            selected: selectedIndex == 0,
            aspectRatio: 16 / 10,
            onTap: () => onPhotoTap?.call(0),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final cross = constraints.maxWidth >= 420 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: urls.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cross,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  return _GalleryCell(
                    url: urls[index],
                    index: index,
                    total: urls.length,
                    selected: index == selectedIndex,
                    aspectRatio: null,
                    onTap: () => onPhotoTap?.call(index),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}

class _GalleryCell extends StatelessWidget {
  const _GalleryCell({
    required this.url,
    required this.index,
    required this.total,
    required this.onTap,
    required this.selected,
    this.aspectRatio,
  });

  final String url;
  final int index;
  final int total;
  final VoidCallback? onTap;
  final bool selected;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final semantic = AppTexts.t('events_gallery_photo_semantics')
        .replaceAll('{current}', '${index + 1}')
        .replaceAll('{total}', '$total');

    final image = Semantics(
      button: true,
      label: semantic,
      child: Material(
        color: EventGalleryGrid.cellBg,
        borderRadius: BorderRadius.circular(EventGalleryGrid.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: EventGalleryGrid.navySoft,
              border: selected
                  ? Border.all(color: EventGalleryGrid.selectedBorder, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(EventGalleryGrid.radius),
            ),
            child: Image.network(
              url,
              key: ValueKey('gallery_cell_$url'),
              fit: BoxFit.contain,
              alignment: Alignment.center,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const ColoredBox(
                  color: EventGalleryGrid.cellBg,
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => ColoredBox(
                color: EventGalleryGrid.cellBg,
                child: Center(
                  child: Semantics(
                    label: AppTexts.t('events_photo_load_error'),
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (aspectRatio == null) return image;
    return AspectRatio(aspectRatio: aspectRatio!, child: image);
  }
}
