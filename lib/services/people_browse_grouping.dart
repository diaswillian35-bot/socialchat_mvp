import '../services/brazil_states.dart';
import '../utils/comcam_region.dart';
import '../utils/user_search_normalize.dart';

class PeopleBrowseProfile {
  const PeopleBrowseProfile({
    required this.uid,
    required this.name,
    required this.city,
    required this.state,
    this.photoUrl = '',
    this.countryCode = '',
  });

  final String uid;
  final String name;
  final String city;
  final String state;
  final String photoUrl;
  final String countryCode;
}

class PeopleBrowseCitySection {
  const PeopleBrowseCitySection({
    required this.title,
    required this.profiles,
    required this.isOtherCitiesBucket,
  });

  final String title;
  final List<PeopleBrowseProfile> profiles;
  final bool isOtherCitiesBucket;
}

class PeopleBrowseStateGroup {
  const PeopleBrowseStateGroup({
    required this.stateLabel,
    required this.sections,
  });

  final String stateLabel;
  final List<PeopleBrowseCitySection> sections;
}

/// Canonical city/state after fixing legacy / dirty location fields.
class PeopleBrowseLocation {
  const PeopleBrowseLocation({
    required this.stateDisplay,
    required this.stateUf,
    required this.cityDisplay,
    required this.cityKey,
    required this.isComcam,
  });

  /// Full state name for headers, e.g. `Santa Catarina`.
  final String stateDisplay;

  /// UF for profile subtitle, e.g. `SC`. Empty if unknown.
  final String stateUf;

  /// Clean city label, e.g. `Araranguá`.
  final String cityDisplay;

  /// Normalized bucket key (accents stripped).
  final String cityKey;

  final bool isComcam;
}

/// Groups profiles by **state**, then nested city / COMCAM / other-cities sections.
///
/// Never promotes a city to a top-level peer of its state. Never exposes counts.
class PeopleBrowseGrouping {
  PeopleBrowseGrouping._();

  /// `City - UF` wrongly stored as state (legacy).
  static final RegExp _stateCityUf = RegExp(
    r'^(.+?)\s*[-–]\s*([A-Za-z]{2})$',
  );

  static List<PeopleBrowseStateGroup> group({
    required List<PeopleBrowseProfile> profiles,
    required int citySectionMinProfiles,
    String otherCitiesLabel = 'Outras cidades do estado',
  }) {
    final minCity = citySectionMinProfiles < 1 ? 1 : citySectionMinProfiles;

    // stateDisplay → cityKey → profiles (COMCAM uses reserved key)
    final byStateCity = <String, Map<String, List<PeopleBrowseProfile>>>{};
    final stateMeta = <String, PeopleBrowseLocation>{};
    final cityDisplayByKey = <String, Map<String, String>>{};

    for (final p in profiles) {
      final loc = normalizeLocation(city: p.city, state: p.state);
      final stateKey = loc.stateDisplay;
      stateMeta.putIfAbsent(stateKey, () => loc);
      final cityMap = byStateCity.putIfAbsent(stateKey, () => {});
      final key = loc.isComcam ? _comcamBucketKey : loc.cityKey;
      cityMap.putIfAbsent(key, () => []).add(p);
      cityDisplayByKey
          .putIfAbsent(stateKey, () => {})
          .putIfAbsent(key, () => loc.isComcam
              ? ComcamRegion.unifiedRegionLabel
              : loc.cityDisplay);
    }

    final stateKeys = byStateCity.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final out = <PeopleBrowseStateGroup>[];
    for (final stateKey in stateKeys) {
      final cityMap = byStateCity[stateKey]!;
      final labels = cityDisplayByKey[stateKey]!;
      final featured = <PeopleBrowseCitySection>[];
      final others = <PeopleBrowseProfile>[];

      // COMCAM always nests under Paraná when present (special region, not a state).
      if (cityMap.containsKey(_comcamBucketKey)) {
        final comcam = cityMap[_comcamBucketKey]!;
        featured.add(
          PeopleBrowseCitySection(
            title: ComcamRegion.unifiedRegionLabel,
            profiles: comcam,
            isOtherCitiesBucket: false,
          ),
        );
      }

      final normalKeys = cityMap.keys
          .where((k) => k != _comcamBucketKey)
          .toList()
        ..sort((a, b) =>
            (labels[a] ?? a).toLowerCase().compareTo((labels[b] ?? b).toLowerCase()));

      for (final cityKey in normalKeys) {
        final bucket = cityMap[cityKey]!;
        if (bucket.length >= minCity) {
          featured.add(
            PeopleBrowseCitySection(
              title: labels[cityKey] ?? cityKey,
              profiles: bucket,
              isOtherCitiesBucket: false,
            ),
          );
        } else {
          others.addAll(bucket);
        }
      }

      // Stable order inside "other cities": by display city under name.
      others.sort((a, b) {
        final la = displayCityUnderName(a).toLowerCase();
        final lb = displayCityUnderName(b).toLowerCase();
        final c = la.compareTo(lb);
        if (c != 0) return c;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      final sections = <PeopleBrowseCitySection>[
        ...featured,
        if (others.isNotEmpty)
          PeopleBrowseCitySection(
            title: otherCitiesLabel,
            profiles: others,
            isOtherCitiesBucket: true,
          ),
      ];

      out.add(
        PeopleBrowseStateGroup(stateLabel: stateKey, sections: sections),
      );
    }
    return out;
  }

  static const String _comcamBucketKey = '__comcam__';

  /// Fixes legacy dirty city/state pairs before grouping.
  static PeopleBrowseLocation normalizeLocation({
    required String city,
    required String state,
  }) {
    var stateRaw = state.trim();
    var cityRaw = city.trim();

    // 1) state = "Araranguá - SC" → city Araranguá, state SC
    final m = _stateCityUf.firstMatch(stateRaw);
    if (m != null) {
      final maybeUf = m.group(2)!;
      final info = BrazilStates.resolve(maybeUf);
      if (info != null) {
        final cityFromState = m.group(1)!.trim();
        stateRaw = info.uf;
        if (_cityLooksDirty(cityRaw) ||
            cityRaw.isEmpty ||
            UserSearchNormalize.normalize(cityRaw)
                .contains(UserSearchNormalize.normalize(cityFromState))) {
          cityRaw = cityFromState;
        }
      }
    }

    // 2) city may still be "Araranguá sc - Rua …"
    if (cityRaw.contains(' - ') || cityRaw.contains(' – ')) {
      cityRaw = cityRaw.split(RegExp(r'\s*[-–]\s*')).first.trim();
    }
    cityRaw = _stripTrailingUf(cityRaw);

    final isComcam = ComcamRegion.isComcamCity(cityRaw);
    BrazilStateInfo? info = BrazilStates.resolve(stateRaw);
    if (info == null && isComcam) {
      info = BrazilStates.resolve('PR');
    }

    final stateDisplay = info?.name ??
        (stateRaw.isEmpty ? '—' : BrazilStates.displayName(stateRaw));
    final stateUf = info?.uf ?? BrazilStates.displayUf(stateRaw);
    final cityDisplay = cityRaw.isEmpty ? '—' : cityRaw;
    final cityKey = cityRaw.isEmpty
        ? '—'
        : UserSearchNormalize.normalize(cityRaw);

    return PeopleBrowseLocation(
      stateDisplay: stateDisplay.isEmpty ? '—' : stateDisplay,
      stateUf: stateUf,
      cityDisplay: cityDisplay,
      cityKey: cityKey,
      isComcam: isComcam,
    );
  }

  static bool _cityLooksDirty(String city) {
    final c = city.trim();
    if (c.isEmpty) return true;
    final lower = c.toLowerCase();
    if (c.contains(' - ') || c.contains(' – ')) return true;
    if (lower.contains('rua ') ||
        lower.contains('av.') ||
        lower.contains('avenida') ||
        lower.contains('bairro')) {
      return true;
    }
    return false;
  }

  static String _stripTrailingUf(String city) {
    final m = RegExp(r'^(.*?)\s+([A-Za-z]{2})$').firstMatch(city.trim());
    if (m == null) return city.trim();
    final uf = m.group(2)!;
    if (BrazilStates.resolve(uf) != null) {
      return m.group(1)!.trim();
    }
    return city.trim();
  }

  /// Profile subtitle: `Araranguá, SC` (UF only beside city, never as state header).
  static String displayCityUnderName(PeopleBrowseProfile p) {
    final loc = normalizeLocation(city: p.city, state: p.state);
    if (loc.cityDisplay.isEmpty || loc.cityDisplay == '—') return '';
    if (loc.stateUf.isNotEmpty) {
      return '${loc.cityDisplay}, ${loc.stateUf}';
    }
    return loc.cityDisplay;
  }

  static String normalizedCityQuery(String q) =>
      UserSearchNormalize.normalize(q);
}
