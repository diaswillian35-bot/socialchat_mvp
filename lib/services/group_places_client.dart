import 'dart:convert';

import 'package:http/http.dart' as http;

import 'group_create_flow.dart';

/// Places autocomplete for group city selection.
///
/// The first segment of the suggestion is the selected place. A later
/// segment such as Toronto is the parent area and is not the city name.
class GroupPlacesClient {
  GroupPlacesClient._();

  static const String apiKey =
      'AIzaSyCCu5KXXT2tSqL4kqwjDX6ySv49lqyCLs0';

  static GroupCityCandidate? parseDescription({
    required String description,
    required String placeId,
  }) {
    final id = placeId.trim();
    final parts = description
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (id.isEmpty || parts.isEmpty) return null;
    final cityName = parts.first;
    if (cityName.isEmpty) return null;
    final stateName = parts.length >= 3 ? parts[parts.length - 2] : '';
    final countryName = parts.length >= 2 ? parts.last : '';
    return GroupCityCandidate(
      cityName: cityName,
      stateName: stateName,
      countryName: countryName,
      display: description.trim(),
      placeId: id,
    );
  }

  static Future<List<GroupCityCandidate>> search({
    required String apiKey,
    required String countryIso2,
    required String input,
  }) async {
    final query = input.trim();
    final country = countryIso2.trim();
    if (query.length < 2 || country.isEmpty || apiKey.trim().isEmpty) {
      return const [];
    }
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeComponent(query)}'
      '&components=country:${Uri.encodeComponent(country)}'
      '&language=pt-BR'
      '&key=${Uri.encodeComponent(apiKey.trim())}',
    );
    final res = await http.get(url);
    if (res.statusCode != 200) return const [];
    final data = jsonDecode(res.body);
    if (data is! Map) return const [];
    final predictions = data['predictions'];
    if (predictions is! List) return const [];
    final out = <GroupCityCandidate>[];
    for (final raw in predictions) {
      if (raw is! Map) continue;
      final parsed = parseDescription(
        description: (raw['description'] ?? '').toString(),
        placeId: (raw['place_id'] ?? '').toString(),
      );
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  static Future<Map<String, double>?> coordinates({
    required String apiKey,
    required String placeId,
  }) async {
    final id = placeId.trim();
    if (id.isEmpty || apiKey.trim().isEmpty) return null;
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=${Uri.encodeComponent(id)}'
      '&fields=geometry'
      '&key=${Uri.encodeComponent(apiKey.trim())}',
    );
    final res = await http.get(url);
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    if (data is! Map) return null;
    final result = data['result'];
    if (result is! Map) return null;
    final geometry = result['geometry'];
    if (geometry is! Map) return null;
    final location = geometry['location'];
    if (location is! Map) return null;
    final lat = location['lat'];
    final lng = location['lng'];
    if (lat is! num || lng is! num) return null;
    return {
      'latitude': lat.toDouble(),
      'longitude': lng.toDouble(),
    };
  }
}
