import 'package:flutter/material.dart';

/// Ordem dos carrosséis da Home: destaques (pagos, no futuro) na frente,
/// sem itens repetidos e, quando possível, sem o mesmo dono/empresa duas
/// vezes na mesma página de [perPage].
/// Máximo de itens por carrossel da Home: 4 páginas de 3 (os espaços
/// vendáveis). "Ver todos" continua abrindo a lista completa.
const int kHomeCarouselMaxItems = 12;

List<T> homeCarouselOrder<T>(
  List<T> items, {
  required String Function(T) idOf,
  String Function(T)? ownerOf,
  bool Function(T)? isFeatured,
  int perPage = 3,
}) {
  final seen = <String>{};
  final unique = <T>[];
  for (final item in items) {
    final id = idOf(item);
    if (id.isEmpty || seen.add(id)) unique.add(item);
  }
  final featured = isFeatured == null
      ? <T>[]
      : unique.where(isFeatured).toList(growable: false);
  final rest = isFeatured == null
      ? unique
      : unique.where((e) => !isFeatured(e)).toList(growable: false);
  if (ownerOf == null || perPage < 2) return [...featured, ...rest];

  List<T> spread(List<T> input, List<T> out) {
    final pending = [...input];
    while (pending.isNotEmpty) {
      final pageStart = out.length - out.length % perPage;
      final owners = {
        for (var i = pageStart; i < out.length; i++) ownerOf(out[i]),
      };
      var pick = pending.indexWhere((e) {
        final o = ownerOf(e);
        return o.isEmpty || !owners.contains(o);
      });
      if (pick < 0) pick = 0;
      out.add(pending.removeAt(pick));
    }
    return out;
  }

  final out = <T>[];
  spread(featured, out);
  spread(rest, out);
  return out;
}

/// Carrossel horizontal da Home: [perPage] cards lado a lado por página,
/// passando de página em página (snap). Pontos só com mais de uma página.
class HomePagedCarousel extends StatefulWidget {
  const HomePagedCarousel({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.height,
    this.perPage = 3,
    this.gap = 8,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;
  final int perPage;
  final double gap;

  static int pageCountFor(int itemCount, int perPage) =>
      itemCount <= 0 ? 0 : (itemCount + perPage - 1) ~/ perPage;

  @override
  State<HomePagedCarousel> createState() => _HomePagedCarouselState();
}

class _HomePagedCarouselState extends State<HomePagedCarousel> {
  static const Color _remdyBlue = Color(0xFF313A5F);

  final PageController _controller = PageController();
  int _page = 0;

  @override
  void didUpdateWidget(covariant HomePagedCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pages =
        HomePagedCarousel.pageCountFor(widget.itemCount, widget.perPage);
    if (_page >= pages && pages > 0) {
      _page = pages - 1;
      if (_controller.hasClients) _controller.jumpToPage(_page);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final perPage = widget.perPage;
    final pages = HomePagedCarousel.pageCountFor(widget.itemCount, perPage);
    if (pages == 0) return const SizedBox.shrink();
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // Cada página tem a largura do conteúdo + o respiro entre páginas,
            // então os cards ficam alinhados às margens e todos do mesmo
            // tamanho; o respiro extra fica à direita, sobre a margem da tela.
            return SizedBox(
              height: widget.height,
              width: width,
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: width + widget.gap,
                maxWidth: width + widget.gap,
                child: PageView.builder(
                  key: const Key('home_paged_carousel'),
                  controller: _controller,
                  itemCount: pages,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, page) {
                    final start = page * perPage;
                    return Padding(
                      padding: EdgeInsets.only(right: widget.gap),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var slot = 0; slot < perPage; slot++) ...[
                            if (slot > 0) SizedBox(width: widget.gap),
                            Expanded(
                              child: start + slot < widget.itemCount
                                  ? widget.itemBuilder(context, start + slot)
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
        if (pages > 1) ...[
          const SizedBox(height: 8),
          Row(
            key: const Key('home_paged_carousel_dots'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pages, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 14 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? _remdyBlue : const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

/// Selo "Destaque" dos carrosséis (mesma pílula dos selos Hoje/Amanhã).
class HomeFeaturedBadge extends StatelessWidget {
  const HomeFeaturedBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('home_featured_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF313A5F),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
