import 'brazil_states.dart';
import 'group_geo.dart';
import 'user_location_scope.dart';
import '../utils/comcam_region.dart';
import '../utils/user_search_normalize.dart';

class CountryPerson {
  const CountryPerson({
    required this.uid,
    required this.name,
    required this.city,
    required this.subdivision,
    required this.countryCode,
    this.latitude,
    this.longitude,
    this.online = false,
  });

  final String uid;
  final String name;
  final String city;
  final String subdivision;
  final String countryCode;
  final double? latitude;
  final double? longitude;
  final bool online;
}

class CountryCityGroup {
  const CountryCityGroup({
    required this.label,
    required this.people,
    this.distanceKm,
    this.subdivisionKey = '',
  });
  final String label;
  final List<CountryPerson> people;
  final double? distanceKm;

  /// Chave normalizada do estado/província (ex.: `SC`), ou [PeopleCountryHierarchy.otherKey].
  final String subdivisionKey;
}

class CountrySubdivisionGroup {
  const CountrySubdivisionGroup({
    required this.key,
    required this.label,
    required this.cities,
    this.distanceKm,
  });

  /// Chave normalizada (UF no Brasil) ou [PeopleCountryHierarchy.otherKey].
  final String key;

  /// Rótulo de exibição (nome completo do estado quando conhecido).
  final String label;
  final List<CountryCityGroup> cities;
  final double? distanceKm;

  bool get isOther => key == PeopleCountryHierarchy.otherKey;
  int get peopleCount =>
      cities.fold<int>(0, (sum, city) => sum + city.people.length);
}

/// Organiza as pessoas de um país para quem está vendo:
/// 1. Sua cidade (mesmo nome normalizado, mesmo país);
/// 2. Sua região (outras cidades até [defaultRegionKm], por distância;
///    COMCAM unificado para quem está na COMCAM);
/// 3. Outras cidades do seu estado (por distância);
/// 4. Demais estados, do mais próximo ao mais distante.
/// Quem vê de fora do país (ou sem localização nele) recebe só os estados,
/// ordenados por quantidade de pessoas e nome.
class PeopleCountryHierarchy {
  const PeopleCountryHierarchy({
    required this.sameCity,
    required this.region,
    required this.viewerSubdivision,
    required this.remaining,
    required this.viewerLocated,
  });

  /// Grupo final para estado vazio/inválido (ex.: "Brasil").
  static const String otherKey = '__outros__';

  /// Raio da "Sua região" na tela de país. Navegantes alcança Itajaí,
  /// Balneário Camboriú, Penha e Barra Velha, mas não Florianópolis/Joinville.
  static const double defaultRegionKm = 60;

  final CountryCityGroup? sameCity;
  final List<CountryCityGroup> region;

  /// Outras cidades do estado de quem está vendo (fora cidade/região).
  final CountrySubdivisionGroup? viewerSubdivision;

  /// Demais estados (com "Outros" sempre por último).
  final List<CountrySubdivisionGroup> remaining;

  /// Quem vê mora no país exibido (há seções de cidade/região/estado).
  final bool viewerLocated;

  static PeopleCountryHierarchy build({
    required List<CountryPerson> people,
    required Map<String, dynamic>? viewer,
    double regionKm = defaultRegionKm,
  }) {
    final pageCountry =
        people.isEmpty ? '' : people.first.countryCode.toLowerCase();
    final viewerCountry = UserLocationScope.countryCodeFromUserData(viewer);
    final viewerCityRaw = UserLocationScope.cityNameFromUserData(viewer);
    final viewerCity =
        UserSearchNormalize.normalize(cleanCity(viewerCityRaw, viewerCountry));
    final viewerStateKey = subdivisionKey(
        UserLocationScope.stateLabelFromUserData(viewer), viewerCountry);
    final viewerLocated = viewerCountry.isNotEmpty &&
        viewerCountry == pageCountry &&
        (viewerCity.isNotEmpty ||
            UserLocationScope.resolveCanonicalCoords(viewer) != null);
    final viewerCoords =
        viewerLocated ? UserLocationScope.resolveCanonicalCoords(viewer) : null;

    final byCity = <String, List<CountryPerson>>{};
    for (final person in people) {
      byCity.putIfAbsent(_cityKey(person), () => <CountryPerson>[]).add(person);
    }
    for (final bucket in byCity.values) {
      bucket.sort(_personOrder);
    }

    CountryCityGroup? sameCity;
    final region = <CountryCityGroup>[];
    final comcam = <CountryCityGroup>[];
    final rest = <String, List<CountryCityGroup>>{};
    final viewerIsComcam = viewerLocated &&
        viewerCountry == 'br' &&
        ComcamRegion.isComcamCity(viewerCityRaw);

    for (final bucket in byCity.values) {
      final first = bucket.first;
      final stateKey = subdivisionKey(first.subdivision, first.countryCode);
      final cityLabel = cleanCity(first.city, first.countryCode);
      final city = UserSearchNormalize.normalize(cityLabel);
      final distance = _distance(viewerCoords, bucket);
      final group = CountryCityGroup(
        label: cityLabel.isEmpty ? '—' : cityLabel,
        people: bucket,
        distanceKm: distance,
        subdivisionKey: stateKey,
      );
      final sameStateOrUnknown = viewerStateKey == otherKey ||
          stateKey == otherKey ||
          stateKey == viewerStateKey;
      if (viewerLocated &&
          viewerCity.isNotEmpty &&
          city == viewerCity &&
          sameStateOrUnknown &&
          sameCity == null) {
        sameCity = group;
      } else if (viewerIsComcam && ComcamRegion.isComcamCity(first.city)) {
        comcam.add(group);
      } else if (viewerLocated &&
          city.isNotEmpty &&
          distance != null &&
          distance <= regionKm) {
        region.add(group);
      } else {
        rest.putIfAbsent(stateKey, () => <CountryCityGroup>[]).add(group);
      }
    }

    region.sort(_cityDistanceOrder);
    if (comcam.isNotEmpty) {
      final merged = comcam.expand((g) => g.people).toList()
        ..sort(_personOrder);
      final distances =
          comcam.map((g) => g.distanceKm).whereType<double>().toList();
      region.insert(
        0,
        CountryCityGroup(
          label: ComcamRegion.unifiedRegionLabel,
          people: merged,
          distanceKm: distances.isEmpty
              ? null
              : distances.reduce((a, b) => a < b ? a : b),
          subdivisionKey: 'PR',
        ),
      );
    }

    final states = rest.entries.map((entry) {
      final cities = entry.value
        ..sort(viewerLocated ? _cityDistanceOrder : _cityNameOrder);
      final distances =
          cities.map((c) => c.distanceKm).whereType<double>().toList();
      return CountrySubdivisionGroup(
        key: entry.key,
        label: subdivisionLabel(entry.key, entry.value),
        cities: cities,
        distanceKm: distances.isEmpty
            ? null
            : distances.reduce((a, b) => a < b ? a : b),
      );
    }).toList();

    CountrySubdivisionGroup? viewerSubdivision;
    if (viewerLocated && viewerStateKey != otherKey) {
      final idx = states.indexWhere((s) => s.key == viewerStateKey);
      if (idx >= 0) viewerSubdivision = states.removeAt(idx);
    }

    states.sort((a, b) {
      if (a.isOther != b.isOther) return a.isOther ? 1 : -1;
      if (viewerLocated) {
        final d = (a.distanceKm ?? double.infinity)
            .compareTo(b.distanceKm ?? double.infinity);
        if (d != 0) return d;
      }
      final count = b.peopleCount.compareTo(a.peopleCount);
      if (count != 0) return count;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });

    return PeopleCountryHierarchy(
      sameCity: sameCity,
      region: region,
      viewerSubdivision: viewerSubdivision,
      remaining: states,
      viewerLocated: viewerLocated,
    );
  }

  /// Chave de agrupamento do estado/província.
  /// Brasil: "SC", "Santa Catarina", "Araranguá - SC" → `SC`;
  /// vazio ou inválido ("Brasil") → [otherKey].
  static String subdivisionKey(String raw, String countryCode) {
    final value = raw.trim();
    if (value.isEmpty) return otherKey;
    if (countryCode.toLowerCase() == 'br') {
      final direct = BrazilStates.resolve(value);
      if (direct != null) return direct.uf;
      final parts = value
          .split(RegExp(r'[-,/–(]'))
          .map((e) => e.replaceAll(')', '').trim())
          .where((e) => e.isNotEmpty)
          .toList();
      for (final part in parts.reversed) {
        final info = BrazilStates.resolve(part);
        if (info != null) return info.uf;
      }
      return otherKey;
    }
    final norm = UserSearchNormalize.normalize(value);
    if (norm.isEmpty || norm == UserSearchNormalize.normalize(countryCode)) {
      return otherKey;
    }
    return norm;
  }

  static String subdivisionLabel(String key, List<CountryCityGroup> cities) {
    if (key == otherKey) return 'Outros';
    final info = BrazilStates.resolve(key);
    if (info != null &&
        cities.isNotEmpty &&
        cities.first.people.isNotEmpty &&
        cities.first.people.first.countryCode.toLowerCase() == 'br') {
      return info.name;
    }
    for (final city in cities) {
      for (final p in city.people) {
        final label = p.subdivision.trim();
        if (label.isNotEmpty) return label;
      }
    }
    return key;
  }

  static int _cityDistanceOrder(CountryCityGroup a, CountryCityGroup b) {
    final noCity = (a.label == '—' ? 1 : 0) - (b.label == '—' ? 1 : 0);
    if (noCity != 0) return noCity;
    final distance = (a.distanceKm ?? double.infinity)
        .compareTo(b.distanceKm ?? double.infinity);
    return distance != 0 ? distance : _cityNameOrder(a, b);
  }

  static int _cityNameOrder(CountryCityGroup a, CountryCityGroup b) {
    final noCity = (a.label == '—' ? 1 : 0) - (b.label == '—' ? 1 : 0);
    if (noCity != 0) return noCity;
    return UserSearchNormalize.normalize(a.label)
        .compareTo(UserSearchNormalize.normalize(b.label));
  }

  static int _personOrder(CountryPerson a, CountryPerson b) {
    if (a.online != b.online) return a.online ? -1 : 1;
    final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return name != 0 ? name : a.uid.compareTo(b.uid);
  }

  /// Limpa o nome da cidade para agrupar/exibir no Brasil:
  /// "Itajaí - SC" → "Itajaí"; "Araranguá sc - Rua X" → "Araranguá".
  static String cleanCity(String raw, String countryCode) {
    var value = raw.trim();
    if (value.isEmpty || countryCode.toLowerCase() != 'br') return value;
    value = value.split(RegExp(r'\s[-–]\s|,|/')).first.trim();
    final m = RegExp(r'^(.*\S)\s+([A-Za-z]{2})$').firstMatch(value);
    if (m != null && BrazilStates.resolve(m.group(2)) != null) {
      value = m.group(1)!.trim();
    }
    return value;
  }

  static String _cityKey(CountryPerson person) {
    final city = UserSearchNormalize.normalize(
        cleanCity(person.city, person.countryCode));
    final state = subdivisionKey(person.subdivision, person.countryCode);
    return '${person.countryCode.toLowerCase()}|$state|${city.isEmpty ? '—' : city}';
  }

  static double? _distance(GroupLatLng? viewer, List<CountryPerson> people) {
    if (viewer == null) return null;
    for (final person in people) {
      if (!UserLocationScope.isValidCityCoordinate(
          person.latitude, person.longitude)) {
        continue;
      }
      return GroupGeo.distanceKm(
          lat1: viewer.latitude,
          lng1: viewer.longitude,
          lat2: person.latitude!,
          lng2: person.longitude!);
    }
    return null;
  }

  static bool isComcam(CountryPerson person) =>
      person.countryCode.toLowerCase() == 'br' &&
      ComcamRegion.isComcamCity(person.city);
}
