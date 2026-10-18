import 'package:flutter/material.dart';

/// Uma foto exibida no visualizador em tela cheia.
class PlaceViewerPhoto {
  const PlaceViewerPhoto({required this.url, this.label = ''});

  /// URL https da imagem. Nula = sem imagem (mostra um ícone).
  final String? url;
  final String label;
}

/// Só aceita https sem credenciais (mesma regra do PlaceCover).
String? placeSafeImageUrl(String? raw) {
  final uri = Uri.tryParse((raw ?? '').trim());
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri.toString()
      : null;
}

/// Abre as fotos em tela cheia, começando na [initialIndex].
Future<void> showPlacePhotoViewer(
  BuildContext context, {
  required List<PlaceViewerPhoto> photos,
  required int initialIndex,
  required String closeLabel,
}) {
  if (photos.isEmpty) return Future.value();
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => PlacePhotoViewer(
        photos: photos,
        initialIndex: initialIndex.clamp(0, photos.length - 1),
        closeLabel: closeLabel,
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Visualizador em tela cheia: fundo escuro, pinça para zoom, deslizar para
/// os lados entre as fotos, fechar no X ou arrastando para baixo.
class PlacePhotoViewer extends StatefulWidget {
  const PlacePhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.closeLabel,
  });

  final List<PlaceViewerPhoto> photos;
  final int initialIndex;
  final String closeLabel;

  @override
  State<PlacePhotoViewer> createState() => _PlacePhotoViewerState();
}

class _PlacePhotoViewerState extends State<PlacePhotoViewer> {
  static const double _dismissDistance = 120;

  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  final _transform = TransformationController();
  bool _zoomed = false;

  // Arrastar para baixo (só sem zoom e com um dedo).
  final Set<int> _pointers = {};
  Offset? _dragStart;
  double _dragY = 0;
  bool _dragging = false;

  @override
  void dispose() {
    _pages.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _updateZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _toggleZoom(TapDownDetails? details, Size size) {
    if (_zoomed) {
      _transform.value = Matrix4.identity();
    } else {
      final p = details?.localPosition ?? size.center(Offset.zero);
      const s = 2.5;
      _transform.value = Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _updateZoom();
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers.add(e.pointer);
    if (_pointers.length == 1 && !_zoomed) {
      _dragStart = e.position;
    } else {
      _cancelDrag();
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    final start = _dragStart;
    if (start == null || _pointers.length != 1 || _zoomed) return;
    final delta = e.position - start;
    if (!_dragging) {
      // Só vira "arrastar para fechar" se o gesto for claramente vertical.
      if (delta.dy > 18 && delta.dy.abs() > delta.dx.abs() * 1.5) {
        _dragging = true;
      } else if (delta.dx.abs() > 18) {
        _dragStart = null;
        return;
      } else {
        return;
      }
    }
    setState(() => _dragY = delta.dy.clamp(0, double.infinity).toDouble());
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_dragging && _dragY > _dismissDistance) {
      Navigator.of(context).maybePop();
      return;
    }
    _cancelDrag();
  }

  void _cancelDrag() {
    _dragStart = null;
    if (_dragging || _dragY != 0) {
      setState(() {
        _dragging = false;
        _dragY = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.photos.length;
    final fade = (1 - _dragY / 400).clamp(0.3, 1.0);
    return Scaffold(
      key: const Key('place_photo_viewer'),
      backgroundColor: Colors.black.withValues(alpha: 0.96 * fade),
      body: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                duration: _dragging
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                transform: Matrix4.translationValues(0, _dragY, 0),
                child: PageView.builder(
                  key: const Key('place_photo_viewer_pages'),
                  controller: _pages,
                  physics: _zoomed || _dragging
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: count,
                  onPageChanged: (i) {
                    _transform.value = Matrix4.identity();
                    setState(() {
                      _index = i;
                      _zoomed = false;
                    });
                  },
                  itemBuilder: (context, i) => _page(widget.photos[i], i),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('place_photo_viewer_close'),
                        tooltip: widget.closeLabel,
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.45),
                        ),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 26),
                      ),
                      const Spacer(),
                      if (count > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_index + 1} / $count',
                            key: const Key('place_photo_viewer_counter'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page(PlaceViewerPhoto photo, int i) {
    final url = photo.url;
    final image = url == null
        ? const Icon(Icons.image_not_supported_outlined,
            color: Colors.white54, size: 56)
        : Image.network(
            url,
            key: Key('place_photo_viewer_image_$i'),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
            errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 56),
          );
    final body = Semantics(
      label: photo.label,
      image: true,
      child: Center(child: image),
    );
    // Só a página atual tem zoom; as vizinhas ficam no tamanho normal.
    if (i != _index) return body;
    return LayoutBuilder(
      builder: (context, constraints) {
        TapDownDetails? lastTap;
        return GestureDetector(
          onDoubleTapDown: (d) => lastTap = d,
          onDoubleTap: () => _toggleZoom(lastTap, constraints.biggest),
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 5,
            panEnabled: _zoomed,
            onInteractionUpdate: (_) => _updateZoom(),
            onInteractionEnd: (_) => _updateZoom(),
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: body,
            ),
          ),
        );
      },
    );
  }
}
