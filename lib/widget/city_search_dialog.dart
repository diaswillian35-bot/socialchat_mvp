import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CitySearchResult {
  final String cityName;
  final String stateName;
  final String displayLocation;
  final String placeId;
  final double? lat;
  final double? lng;

  CitySearchResult({
    required this.cityName,
    required this.stateName,
    required this.displayLocation,
    required this.placeId,
    this.lat,
    this.lng,
  });
}

class CitySearchDialog {
  static Future<CitySearchResult?> open({
    required BuildContext context,
    required String countryCode,
    required String googleApiKey,
  }) async {
    final searchC = TextEditingController();
    List<CitySearchResult> results = [];
    bool loading = false;

    Future<List<CitySearchResult>> searchCities(String input) async {
      final q = input.trim();
      if (q.length < 2) return [];
      if (countryCode.trim().isEmpty) return [];

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(q)}'
        '&components=country:${countryCode.toUpperCase()}'
        
'&types=(cities)'
'&language=pt-BR'
'&key=$googleApiKey',


      );

      final res = await http.get(url);
      if (res.statusCode != 200) return [];

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final predictions = (data['predictions'] as List<dynamic>? ?? []);

      return predictions.map((p) {
        final description = (p['description'] ?? '').toString();
        final placeId = (p['place_id'] ?? '').toString();

        final parts = description.split(',').map((e) => e.trim()).toList();

        final cityName = parts.isNotEmpty ? parts[0] : '';
        final stateName = parts.length >= 2 ? parts[1] : '';

        return CitySearchResult(
          cityName: cityName,
          stateName: stateName,
          displayLocation: description,
          placeId: placeId,
        );
      }).where((e) => e.cityName.isNotEmpty).toList();
    }

    Future<CitySearchResult> loadDetails(CitySearchResult item) async {
      if (item.placeId.isEmpty) return item;

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${Uri.encodeComponent(item.placeId)}'
        '&fields=geometry'
        '&key=$googleApiKey',
      );

      final res = await http.get(url);
      if (res.statusCode != 200) return item;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final location = data['result']?['geometry']?['location'];

      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();

      return CitySearchResult(
        cityName: item.cityName,
        stateName: item.stateName,
        displayLocation: item.displayLocation,
        placeId: item.placeId,
        lat: lat,
        lng: lng,
      );
    }

    return showModalBottomSheet<CitySearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> runSearch(String value) async {
              if (value.trim().length < 2) {
                setModalState(() {
                  results = [];
                  loading = false;
                });
                return;
              }

              setModalState(() => loading = true);

              final found = await searchCities(value);

              setModalState(() {
                results = found;
                loading = false;
              });
            }

            return SafeArea(
              child: Container(
                height: MediaQuery.of(context).size.height * 0.78,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Escolha sua cidade',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchC,
                      autofocus: true,
                      onChanged: runSearch,
                      decoration: InputDecoration(
                        hintText: 'Buscar cidade',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : results.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Digite pelo menos 2 letras da cidade',
                                    style: TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: results.length,
                                  itemBuilder: (context, i) {
                                    final item = results[i];

                                    return ListTile(
                                      title: Text(item.displayLocation),
                                      onTap: () async {
                                        final full =
                                            await loadDetails(item);

                                        if (!context.mounted) return;
                                        Navigator.pop(context, full);
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
