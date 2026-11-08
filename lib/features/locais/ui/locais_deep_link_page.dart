import 'package:flutter/material.dart';

import '../../../services/remdy_launch_access.dart';
import '../data/place_repository.dart';
import '../logic/place_country_access.dart';
import '../locais_strings.dart';
import 'locais_detail_page.dart';
import 'locais_state_views.dart';

class LocaisDeepLinkPage extends StatefulWidget {
  const LocaisDeepLinkPage(
      {super.key,
      this.slug,
      this.placeId,
      this.repository,
      this.homeCountryLoader});
  final String? slug;
  final String? placeId;
  final PlaceRepository? repository;
  final HomeCountryLoader? homeCountryLoader;

  @override
  State<LocaisDeepLinkPage> createState() => _LocaisDeepLinkPageState();
}

class _LocaisDeepLinkPageState extends State<LocaisDeepLinkPage> {
  late final PlaceRepository _repository =
      widget.repository ?? createPlaceRepository();
  late final Future<String?> _placeId = _resolve();

  bool _countryDenied = false;

  Future<String?> _resolve() async {
    // Detail page fetches this document directly via fetchById.
    String? id = widget.placeId;
    if (id == null) {
      final catalog = await _repository.fetchCatalog();
      for (final place in catalog) {
        if (place.slug == widget.slug) {
          id = place.id;
          break;
        }
      }
    }
    if (id == null) return null;
    // Local de outro país: mesma mensagem dos grupos, sem abrir a ficha.
    final place = await _repository.fetchById(id);
    final home = await (widget.homeCountryLoader ?? loadCurrentHomeCountryCode)();
    if (place != null && !canSeePlaceCountry(place, home)) {
      _countryDenied = true;
      return null;
    }
    return id;
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
        if (_countryDenied) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!context.mounted) return;
            await RemdyLaunchAccess.showUnavailable(context);
            if (context.mounted) Navigator.of(context).maybePop();
          });
          return const Scaffold(body: SizedBox.shrink());
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
          repository: _repository,
        );
      },
    );
  }
}
