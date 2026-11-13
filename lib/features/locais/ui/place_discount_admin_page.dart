import 'package:flutter/material.dart';

import '../../../l10n/app_texts.dart';
import '../data/place_repository.dart';
import '../models/place_listing.dart';
import 'locais_layout.dart';
import 'place_discount_editor_page.dart';

/// Lista de locais publicados para o admin definir a parceria Remdy+local.
class PlaceDiscountAdminPage extends StatefulWidget {
  const PlaceDiscountAdminPage({super.key, this.repository});

  final PlaceRepository? repository;

  @override
  State<PlaceDiscountAdminPage> createState() => _PlaceDiscountAdminPageState();
}

class _PlaceDiscountAdminPageState extends State<PlaceDiscountAdminPage> {
  late final PlaceRepository _repo =
      widget.repository ?? createPlaceRepository();
  Future<List<PlaceListing>>? _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchCatalog();
  }

  Future<void> _reload() async {
    setState(() => _future = _repo.fetchCatalog());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.t;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: LocaisColors.text,
        title: Text(
          t('place_discount_admin_title'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: t('place_discount_pick_place'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<PlaceListing>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text(t('place_discount_error')));
                }
                var items = snap.data ?? const <PlaceListing>[];
                if (_query.isNotEmpty) {
                  items = items
                      .where((p) =>
                          p.name.toLowerCase().contains(_query) ||
                          p.address.city.toLowerCase().contains(_query))
                      .toList();
                }
                return RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final p = items[i];
                      final d = p.discount;
                      final active = d != null && d.isActiveAt(DateTime.now());
                      return ListTile(
                        title: Text(
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          [
                            p.address.city,
                            if (active) '−${d.percent}%',
                            if (active && d.isPartnership)
                              t('place_discount_partner'),
                          ].join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final ok = await PlaceDiscountEditorPage.open(
                            context,
                            placeId: p.id,
                            placeName: p.name,
                            initial: p.discount,
                            partnership: true,
                          );
                          if (ok == true && mounted) _reload();
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
