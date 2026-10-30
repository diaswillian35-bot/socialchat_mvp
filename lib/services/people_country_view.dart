import 'brazil_states.dart';
import 'group_geo.dart';
import 'people_country_hierarchy.dart';
import 'user_interests.dart';
import 'user_location_scope.dart';
import '../utils/user_search_normalize.dart';

/// Cidade natal opcional do perfil ("Sou de...").
///
/// Campos em `users/{uid}`: `hometownCity`, `hometownState`,
/// `hometownCountryCode`, `hometownKey`, `hometownLat`, `hometownLng`.
class HometownInfo {
  const HometownInfo({
    required this.city,
    required this.subdivision,
    required this.countryCode,
    this.latitude,
    this.longitude,
  });

  final String city;
  final String subdivision;
  final String countryCode;
  final double? latitude;
  final double? longitude;

  static HometownInfo? fromUserData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final city = (data['hometownCity'] ?? '').toString().trim();
    final country =
        (data['hometownCountryCode'] ?? '').toString().trim().toLowerCase();
    if (city.isEmpty || country.isEmpty) return null;
    double? asD(Object? v) =>
        v is num ? v.toDouble() : double.tryParse((v ?? '').toString());
    final lat = asD(data['hometownLat']);
    final lng = asD(data['hometownLng']);
    final valid = UserLocationScope.isValidCityCoordinate(lat, lng);
    return HometownInfo(
      city: city,
      subdivision: (data['hometownState'] ?? '').toString().trim(),
      countryCode: country,
      latitude: valid ? lat : null,
      longitude: valid ? lng : null,
    );
  }

  /// Chave normalizada `pais|estado|cidade` (ex.: `br|PR|campo mourao`).
  static String keyFor(String city, String subdivision, String countryCode) {
    final cc = countryCode.trim().toLowerCase();
    final c = UserSearchNormalize.normalize(
        PeopleCountryHierarchy.cleanCity(city, cc));
    if (c.isEmpty || cc.isEmpty) return '';
    var s = PeopleCountryHierarchy.subdivisionKey(subdivision, cc);
    if (s == PeopleCountryHierarchy.otherKey) s = '';
    return '$cc|$s|$c';
  }

  String get key => keyFor(city, subdivision, countryCode);
}

/// Preposição em português para o estado: "do Paraná", "da Bahia",
/// "de Santa Catarina". Fora do Brasil, "de".
String ptStatePreposition(String stateKey) {
  const masc = {
    'AC',
    'AP',
    'AM',
    'CE',
    'DF',
    'ES',
    'MA',
    'MT',
    'MS',
    'PA',
    'PR',
    'PI',
    'RJ',
    'RN',
    'RS',
    'TO',
  };
  const fem = {'BA', 'PB'};
  final k = stateKey.toUpperCase();
  if (masc.contains(k)) return 'do';
  if (fem.contains(k)) return 'da';
  return 'de';
}

/// Mesmo lugar: país e cidade iguais; estado só desempata quando os dois têm.
bool sameHometownPlace(String keyA, String keyB) {
  if (keyA.isEmpty || keyB.isEmpty) return false;
  final a = keyA.split('|');
  final b = keyB.split('|');
  if (a.length != 3 || b.length != 3) return false;
  if (a[0] != b[0] || a[2] != b[2]) return false;
  return a[1].isEmpty || b[1].isEmpty || a[1] == b[1];
}

enum CommonReason {
  sameHometown,
  livesInYourHometown,
  sameCity,
  sharedInterests
}

class CommonMatch {
  const CommonMatch(
      {required this.person,
      required this.reason,
      required this.city,
      this.interests = const []});
  final CountryPerson person;
  final CommonReason reason;

  /// Cidade citada no motivo (ex.: "Campo Mourão").
  final String city;

  /// Interesses em comum (chaves), quando [reason] é sharedInterests.
  final List<String> interests;
}

class CountryPeopleRow {
  const CountryPeopleRow({
    required this.person,
    required this.cityLabel,
    this.distanceKm,
    this.isViewerHometown = false,
  });
  final CountryPerson person;
  final String cityLabel;

  /// Distância até a referência (cidade atual ou natal). Null = não mostrar.
  final double? distanceKm;
  final bool isViewerHometown;
}

class CountryStateSection {
  const CountryStateSection({
    required this.key,
    required this.label,
    required this.rows,
    required this.initiallyOpen,
  });
  final String key;
  final String label;
  final List<CountryPeopleRow> rows;
  final bool initiallyOpen;
  bool get isOther => key == PeopleCountryHierarchy.otherKey;

  /// Pessoas do estado agrupadas por cidade, na ordem das linhas (que já vêm
  /// por distância do usuário; sem referência, por nome da cidade).
  List<CountryCitySection> get cities => CountryCitySection.group(rows);
}

/// Cidade dentro de um estado ("Cidade · N"), começa fechada.
class CountryCitySection {
  const CountryCitySection({required this.label, required this.rows});
  final String label;
  final List<CountryPeopleRow> rows;

  /// Máximo de pessoas por cidade antes do "Ver todas".
  static const int previewCount = 5;

  static List<CountryCitySection> group(List<CountryPeopleRow> rows) {
    final order = <String>[];
    final byKey = <String, List<CountryPeopleRow>>{};
    final labels = <String, String>{};
    for (final r in rows) {
      final label =
          PeopleCountryHierarchy.cleanCity(r.person.city, r.person.countryCode);
      final k = UserSearchNormalize.normalize(label);
      if (!byKey.containsKey(k)) {
        order.add(k);
        labels[k] = label.isEmpty ? '—' : label;
      }
      byKey.putIfAbsent(k, () => <CountryPeopleRow>[]).add(r);
    }
    return [
      for (final k in order)
        CountryCitySection(label: labels[k]!, rows: byKey[k]!)
    ];
  }
}

class CountryStateChip {
  const CountryStateChip(
      {required this.key, required this.label, required this.count});
  final String key;

  /// UF no Brasil; nome do estado/província nos outros países.
  final String label;
  final int count;
  bool get isOther => key == PeopleCountryHierarchy.otherKey;
}

/// Modelo da tela da bandeira (sem Flutter), usado pela página e pelos testes.
class CountryPeopleView {
  const CountryPeopleView({
    required this.total,
    required this.hasReference,
    required this.referenceIsHometown,
    required this.referenceCity,
    required this.referenceCityEmpty,
    required this.nearby,
    required this.ownStateKey,
    required this.ownStateLabel,
    required this.ownStateRows,
    required this.otherStates,
    required this.common,
    required this.chips,
  });

  final int total;

  /// Há uma cidade de referência no país (atual ou natal).
  final bool hasReference;
  final bool referenceIsHometown;
  final String referenceCity;

  /// Ninguém além de quem vê na cidade de referência.
  final bool referenceCityEmpty;

  /// "Perto de você": cidade + região juntas, da mais perto à mais longe.
  final List<CountryPeopleRow> nearby;
  final String ownStateKey;
  final String ownStateLabel;
  final List<CountryPeopleRow> ownStateRows;
  final List<CountryStateSection> otherStates;
  final List<CommonMatch> common;
  final List<CountryStateChip> chips;

  static const int maxCommon = 12;

  /// Mínimo de pessoas em "Em comum" antes de completar com a mesma cidade.
  static const int minCommonFill = 6;
  static const int abroadOpenStates = 2;

  static String stateKeyOf(CountryPerson p) =>
      PeopleCountryHierarchy.subdivisionKey(p.subdivision, p.countryCode);

  static CountryPeopleView build({
    required List<CountryPerson> people,
    required Map<String, dynamic>? viewer,
    required String countryCode,
    String? stateFilter,
  }) {
    final cc = countryCode.trim().toLowerCase();
    final hometown = HometownInfo.fromUserData(viewer);
    final ref = _resolveReference(viewer, hometown, cc, people);
    final refCoords = UserLocationScope.resolveCanonicalCoords(ref?.data);

    double? distanceTo(CountryPerson p) {
      if (refCoords == null) return null;
      if (!UserLocationScope.isValidCityCoordinate(p.latitude, p.longitude)) {
        return null;
      }
      return GroupGeo.distanceKm(
          lat1: refCoords.latitude,
          lng1: refCoords.longitude,
          lat2: p.latitude!,
          lng2: p.longitude!);
    }

    final hometownKey = hometown?.key ?? '';
    final viewerCurrentKey = HometownInfo.keyFor(
        UserLocationScope.cityNameFromUserData(viewer),
        UserLocationScope.stateLabelFromUserData(viewer),
        UserLocationScope.countryCodeFromUserData(viewer));
    final hometownIsCurrent = sameHometownPlace(hometownKey, viewerCurrentKey);
    bool livesInViewerHometown(CountryPerson p) =>
        !hometownIsCurrent &&
        sameHometownPlace(hometownKey,
            HometownInfo.keyFor(p.city, p.subdivision, p.countryCode));

    CountryPeopleRow row(CountryPerson p, {bool showDistance = true}) {
      final d = showDistance ? distanceTo(p) : null;
      final label = PeopleCountryHierarchy.cleanCity(p.city, p.countryCode);
      return CountryPeopleRow(
        person: p,
        cityLabel: label,
        distanceKm: d,
        isViewerHometown: livesInViewerHometown(p),
      );
    }

    // Chips: sempre a partir da lista completa.
    final counts = <String, int>{};
    final minDist = <String, double>{};
    for (final p in people) {
      final k = stateKeyOf(p);
      counts[k] = (counts[k] ?? 0) + 1;
      final d = distanceTo(p);
      if (d != null && d < (minDist[k] ?? double.infinity)) minDist[k] = d;
    }
    final refStateKey = ref == null
        ? ''
        : PeopleCountryHierarchy.subdivisionKey(
            UserLocationScope.stateLabelFromUserData(ref.data), cc);
    final chipKeys = counts.keys.toList()
      ..sort((a, b) {
        final ao = a == PeopleCountryHierarchy.otherKey;
        final bo = b == PeopleCountryHierarchy.otherKey;
        if (ao != bo) return ao ? 1 : -1;
        if (ref != null) {
          if ((a == refStateKey) != (b == refStateKey)) {
            return a == refStateKey ? -1 : 1;
          }
          final d = (minDist[a] ?? double.infinity)
              .compareTo(minDist[b] ?? double.infinity);
          if (d != 0) return d;
        }
        final c = counts[b]!.compareTo(counts[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    final chips = chipKeys
        .map((k) => CountryStateChip(
            key: k, label: _chipLabel(k, cc, people), count: counts[k]!))
        .toList();

    final filtered = (stateFilter == null || stateFilter.isEmpty)
        ? people
        : people.where((p) => stateKeyOf(p) == stateFilter).toList();
    final h = PeopleCountryHierarchy.build(
        people: filtered, viewer: ref?.data, countryCode: cc);

    final nearby = <CountryPeopleRow>[
      if (h.sameCity != null)
        ...h.sameCity!.people
            .where((p) => !p.hideInCity)
            .map((p) => row(p, showDistance: false)),
    ];
    final regionRows = h.region.expand((g) => g.people).map(row).toList();
    _stableSortByKm(regionRows);
    nearby.addAll(regionRows);

    final own = h.viewerSubdivision;
    final ownRows = own == null
        ? <CountryPeopleRow>[]
        : own.cities.expand((c) => c.people).map(row).toList();

    final filteredSingle = stateFilter != null && stateFilter.isNotEmpty;
    final others = <CountryStateSection>[];
    for (var i = 0; i < h.remaining.length; i++) {
      final s = h.remaining[i];
      final open =
          filteredSingle || (ref != null ? i == 0 : i < abroadOpenStates);
      others.add(CountryStateSection(
        key: s.key,
        label: s.label,
        rows: s.cities.expand((c) => c.people).map(row).toList(),
        initiallyOpen: open,
      ));
    }

    // Em comum com você: interesses marcados (lista fixa; "Sobre mim" não
    // entra) de qualquer cidade do país, do maior nº de iguais ao menor.
    // Depois, cidade natal. Quem aparece aqui não se repete abaixo.
    final common = <CommonMatch>[];
    if (!filteredSingle) {
      final viewerInterests = UserInterests.fromUserData(viewer);
      final byInterest = <CommonMatch>[];
      final byHometown = <CommonMatch>[];
      final bySameCity = <CommonMatch>[];
      final sameCityUids = {
        for (final p in h.sameCity?.people ?? const <CountryPerson>[])
          if (!p.hideInCity) p.uid
      };
      for (final p in people) {
        final shared = UserInterests.common(viewerInterests, p.interests);
        if (shared.isNotEmpty) {
          byInterest.add(CommonMatch(
              person: p,
              reason: CommonReason.sharedInterests,
              city: '',
              interests: shared));
          continue;
        }
        final pHome = HometownInfo.keyFor(
            p.hometownCity, p.hometownSubdivision, p.hometownCountryCode);
        if (sameHometownPlace(hometownKey, pHome)) {
          byHometown.add(CommonMatch(
              person: p,
              reason: CommonReason.sameHometown,
              city: hometown!.city));
        } else if (livesInViewerHometown(p)) {
          byHometown.add(CommonMatch(
              person: p,
              reason: CommonReason.livesInYourHometown,
              city: hometown!.city));
        } else if (sameCityUids.contains(p.uid)) {
          bySameCity.add(CommonMatch(
              person: p,
              reason: CommonReason.sameCity,
              city: PeopleCountryHierarchy.cleanCity(p.city, p.countryCode)));
        }
      }
      int tie(CommonMatch a, CommonMatch b) {
        if (a.person.online != b.person.online) return a.person.online ? -1 : 1;
        return a.person.name
            .toLowerCase()
            .compareTo(b.person.name.toLowerCase());
      }

      byInterest.sort((a, b) {
        final c = b.interests.length.compareTo(a.interests.length);
        return c != 0 ? c : tie(a, b);
      });
      byHometown.sort((a, b) {
        final r = a.reason.index.compareTo(b.reason.index);
        return r != 0 ? r : tie(a, b);
      });
      common
        ..addAll(byInterest)
        ..addAll(byHometown);
      // Depois, a mesma cidade (como antes do build 39), completando até
      // [minCommonFill] para a seção nunca ficar vazia quando há alguém.
      if (common.length < minCommonFill) {
        bySameCity.sort(tie);
        common.addAll(bySameCity.take(minCommonFill - common.length));
      }
      if (common.length > maxCommon) {
        common.removeRange(maxCommon, common.length);
      }
      // Mesma cidade continua também em "Perto de você" (é só um atalho).
      final shown = common
          .where((m) => m.reason != CommonReason.sameCity)
          .map((m) => m.person.uid)
          .toSet();
      nearby.removeWhere((r) => shown.contains(r.person.uid));
      ownRows.removeWhere((r) => shown.contains(r.person.uid));
      for (final sec in others) {
        sec.rows.removeWhere((r) => shown.contains(r.person.uid));
      }
      others.removeWhere((sec) => sec.rows.isEmpty);
    }

    final refCityNorm = ref == null
        ? ''
        : UserSearchNormalize.normalize(
            PeopleCountryHierarchy.cleanCity(ref.city, cc));
    final refCityEmpty = ref != null &&
        !people.any((p) =>
            UserSearchNormalize.normalize(
                PeopleCountryHierarchy.cleanCity(p.city, p.countryCode)) ==
            refCityNorm);

    return CountryPeopleView(
      total: people.length,
      hasReference: ref != null,
      referenceIsHometown: ref?.isHometown ?? false,
      referenceCity:
          ref == null ? '' : PeopleCountryHierarchy.cleanCity(ref.city, cc),
      referenceCityEmpty: refCityEmpty,
      nearby: nearby,
      ownStateKey: own?.key ?? '',
      ownStateLabel: own?.label ?? '',
      ownStateRows: ownRows,
      otherStates: others,
      common: common,
      chips: chips,
    );
  }

  static void _stableSortByKm(List<CountryPeopleRow> rows) {
    final indexed = rows.asMap().entries.toList()
      ..sort((a, b) {
        final d = (a.value.distanceKm ?? double.infinity)
            .round()
            .compareTo((b.value.distanceKm ?? double.infinity).round());
        return d != 0 ? d : a.key.compareTo(b.key);
      });
    rows
      ..clear()
      ..addAll(indexed.map((e) => e.value));
  }

  static String _chipLabel(String key, String cc, List<CountryPerson> people) {
    if (key == PeopleCountryHierarchy.otherKey) return key;
    if (cc == 'br') {
      final info = BrazilStates.resolve(key);
      if (info != null) return info.uf;
    }
    for (final p in people) {
      if (stateKeyOf(p) == key && p.subdivision.trim().isNotEmpty) {
        return p.subdivision.trim();
      }
    }
    return key;
  }

  static _Reference? _resolveReference(Map<String, dynamic>? viewer,
      HometownInfo? hometown, String cc, List<CountryPerson> people) {
    final viewerCountry = UserLocationScope.countryCodeFromUserData(viewer);
    final city = UserLocationScope.cityNameFromUserData(viewer);
    if (viewerCountry == cc &&
        (city.isNotEmpty ||
            UserLocationScope.resolveCanonicalCoords(viewer) != null)) {
      return _Reference(data: viewer!, city: city, isHometown: false);
    }
    if (hometown == null || hometown.countryCode != cc) return null;
    var lat = hometown.latitude;
    var lng = hometown.longitude;
    if (lat == null || lng == null) {
      final key = hometown.key;
      for (final p in people) {
        if (!UserLocationScope.isValidCityCoordinate(p.latitude, p.longitude)) {
          continue;
        }
        if (sameHometownPlace(
            key, HometownInfo.keyFor(p.city, p.subdivision, p.countryCode))) {
          lat = p.latitude;
          lng = p.longitude;
          break;
        }
      }
    }
    if (lat == null || lng == null) return null;
    return _Reference(
      data: {
        'homeCountryCode': cc,
        'cityName': hometown.city,
        'stateName': hometown.subdivision,
        'cityLat': lat,
        'cityLng': lng,
      },
      city: hometown.city,
      isHometown: true,
    );
  }
}

class _Reference {
  const _Reference(
      {required this.data, required this.city, required this.isHometown});
  final Map<String, dynamic> data;
  final String city;
  final bool isHometown;
}
