import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_texts.dart';

/// Visualizador fullscreen da Galeria (até 5 fotos): swipe, zoom, contador.
class EventGalleryViewerPage extends StatefulWidget {
  const EventGalleryViewerPage({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  final List<String> urls;
  final int initialIndex;

  /// Retorna o índice ativo ao fechar (mantém seleção na grade).
  static Future<int?> open(
    BuildContext context, {
    required List<String> urls,
    int initialIndex = 0,
  }) {
    if (urls.isEmpty) return Future.value(null);
    final idx = initialIndex.clamp(0, urls.length - 1);
    return Navigator.of(context).push<int>(
      PageRouteBuilder<int>(
        opaque: true,
        barrierColor: const Color(0xFF0B1020),
        pageBuilder: (_, __, ___) => EventGalleryViewerPage(
          urls: List<String>.unmodifiable(urls),
          initialIndex: idx,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  State<EventGalleryViewerPage> createState() => _EventGalleryViewerPageState();
}

class _EventGalleryViewerPageState extends State<EventGalleryViewerPage> {
  late final PageController _pageController;
  late int _index;
  final Map<int, TransformationController> _transforms = {};
  final Map<int, VoidCallback> _transformListeners = {};
  bool _zoomed = false;
  TapDownDetails? _doubleTapDetails;

  static const _bg = Color(0xFF0B1020);

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _pageController = PageController(initialPage: _index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheNeighbors(_index));
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final entry in _transforms.entries) {
      final listener = _transformListeners[entry.key];
      if (listener != null) entry.value.removeListener(listener);
      entry.value.dispose();
    }
    super.dispose();
  }

  TransformationController _transformFor(int i) {
    return _transforms.putIfAbsent(i, () {
      final c = TransformationController();
      void listener() {
        final z = c.value.getMaxScaleOnAxis() > 1.05;
        if (z != _zoomed && i == _index && mounted) {
          setState(() => _zoomed = z);
        }
      }

      _transformListeners[i] = listener;
      c.addListener(listener);
      return c;
    });
  }

  void _precacheNeighbors(int index) {
    if (!mounted) return;
    final ctx = context;
    for (final i in {index - 1, index, index + 1}) {
      if (i < 0 || i >= widget.urls.length) continue;
      precacheImage(NetworkImage(widget.urls[i]), ctx).ignore();
    }
  }

  void _close() {
    Navigator.of(context).maybePop(_index);
  }

  void _toggleZoom(int pageIndex) {
    final details = _doubleTapDetails;
    final controller = _transformFor(pageIndex);
    final current = controller.value.getMaxScaleOnAxis();
    if (current > 1.05) {
      controller.value = Matrix4.identity();
      return;
    }
    final position = details?.localPosition ?? Offset.zero;
    controller.value = Matrix4.identity()
      ..translateByDouble(-position.dx * 1.2, -position.dy * 1.2, 0, 1)
      ..scaleByDouble(2.2, 2.2, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final n = widget.urls.length;
    final label = AppTexts.t('events_photo_viewer_count')
        .replaceAll('{current}', '${_index + 1}')
        .replaceAll('{total}', '$n');
    final semantics = AppTexts.t('events_photo_viewer_semantics')
        .replaceAll('{current}', '${_index + 1}')
        .replaceAll('{total}', '$n');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_index);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: _bg,
          body: Semantics(
            label: semantics,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _pageController,
                  physics: _zoomed
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: n,
                  onPageChanged: (i) {
                    _transformFor(_index).value = Matrix4.identity();
                    setState(() {
                      _index = i;
                      _zoomed = false;
                    });
                    _precacheNeighbors(i);
                  },
                  itemBuilder: (_, i) {
                    final url = widget.urls[i];
                    return GestureDetector(
                      onDoubleTapDown: (d) => _doubleTapDetails = d,
                      onDoubleTap: () => _toggleZoom(i),
                      child: InteractiveViewer(
                        transformationController: _transformFor(i),
                        minScale: 1,
                        maxScale: 4,
                        child: Center(
                          child: Image.network(
                            url,
                            key: ValueKey('viewer_$url'),
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Center(
                                child: Semantics(
                                  label: AppTexts.t('events_photo_loading'),
                                  child: const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => Semantics(
                              label: AppTexts.t('events_photo_load_error'),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.white54,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    AppTexts.t('events_photo_load_error'),
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  top: top + 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: [
                      Material(
                        color: const Color(0x66000000),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: AppTexts.t('events_photo_viewer_close'),
                          onPressed: _close,
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x66000000),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (n > 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottom + 18,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < n; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _index ? 16 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == _index
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
