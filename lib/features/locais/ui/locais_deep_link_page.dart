import 'package:flutter/material.dart';

import '../data/place_repository.dart';
import '../locais_strings.dart';
import 'locais_detail_page.dart';
import 'locais_state_views.dart';

class LocaisDeepLinkPage extends StatefulWidget {
  const LocaisDeepLinkPage({super.key, required this.slug});
  final String slug;

  @override
  State<LocaisDeepLinkPage> createState() => _LocaisDeepLinkPageState();
}

class _LocaisDeepLinkPageState extends State<LocaisDeepLinkPage> {
  late final Future<String?> _placeId = _resolve();

  Future<String?> _resolve() async {
    final catalog = await createPlaceRepository().fetchCatalog();
    for (final place in catalog) {
      if (place.slug == widget.slug) return place.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = LocaisStrings.of(context);
    return FutureBuilder<String?>(
      future: _placeId,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(body: LocaisLoading(label: strings.loading));
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(),
            body:
                LocaisEmpty(title: strings.emptyTitle, body: strings.emptyBody),
          );
        }
        return LocaisDetailPage(
          placeId: snapshot.data!,
          repository: createPlaceRepository(),
        );
      },
    );
  }
}
