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
  const CountryCityGroup(
      {required this.label, required this.people, this.distanceKm});
  final String label;
  final List<CountryPerson> people;
  final double? distanceKm;
}

class CountrySubdivisionGroup {
  const CountrySubdivisionGroup({required this.label, required this.cities});
  final String label;
  final List<CountryCityGroup> cities;
}

class PeopleCountryHierarchy {
  const PeopleCountryHierarchy({
    required this.sameCity,
    required this.region,
    required this.nearbyCities,
    required this.remaining,
  });

  final CountryCityGroup? sameCity;
  final List<CountryCityGroup> region;
  final List<CountryCityGroup> nearbyCities;
  final List<CountrySubdivisionGroup> remaining;

  static PeopleCountryHierarchy build({
    required List<CountryPerson> people,
    required Map<String, dynamic>? viewer,
    double regionKm = UserLocationScope.regionRadiusKm,
    double nearbyKm = 300,
  }) {
    final viewerCoords = UserLocationScope.resolveCanonicalCoords(viewer);
    final viewerCity = UserSearchNormalize.normalize(
        UserLocationScope.cityNameFromUserData(viewer));
    final viewerCountry = UserLocationScope.countryCodeFromUserData(viewer);
    final byCity = <String, List<CountryPerson>>{};
    for (final person in people) {
      byCity.putIfAbsent(_cityKey(person), () => <CountryPerson>[]).add(person);
    }
    for (final bucket in byCity.values) {
      bucket.sort(_personOrder);
    }

    CountryCityGroup? sameCity;
    final region = <CountryCityGroup>[];
    final nearby = <CountryCityGroup>[];
    final remaining = <String, Map<String, CountryCityGroup>>{};

    for (final entry in byCity.entries) {
      final bucket = entry.value;
      final first = bucket.first;
      final cityLabel = first.city.trim().isEmpty ? '—' : first.city.trim();
      final sameCountry = viewerCountry.isNotEmpty &&
          first.countryCode.toLowerCase() == viewerCountry;
      final distance = sameCountry ? _distance(viewerCoords, bucket) : null;
      final sameCanonicalCity = viewerCoords != null &&
          viewerCountry.isNotEmpty &&
          sameCountry &&
          viewerCity.isNotEmpty &&
          UserSearchNormalize.normalize(first.city) == viewerCity &&
          distance != null &&
          distance <= UserLocationScope.sameCityMaxDistanceKm;
      final group = CountryCityGroup(
          label: cityLabel, people: bucket, distanceKm: distance);
      if (sameCanonicalCity) {
        sameCity = group;
      } else if (viewerCoords != null &&
          distance != null &&
          distance <= regionKm) {
        region.add(group);
      } else if (viewerCoords != null &&
          distance != null &&
          distance <= nearbyKm) {
        nearby.add(group);
      } else {
        final subdivision = _subdivisionLabel(first);
        remaining.putIfAbsent(
            subdivision, () => <String, CountryCityGroup>{})[entry.key] = group;
      }
    }

    int cityDistanceOrder(CountryCityGroup a, CountryCityGroup b) {
      final distance = (a.distanceKm ?? double.infinity)
          .compareTo(b.distanceKm ?? double.infinity);
      return distance != 0
          ? distance
          : a.label.toLowerCase().compareTo(b.label.toLowerCase());
    }

    region.sort(cityDistanceOrder);
    nearby.sort(cityDistanceOrder);

    final viewerIsComcam = viewerCountry == 'br' &&
        ComcamRegion.isComcamCity(
            UserLocationScope.cityNameFromUserData(viewer));
    if (viewerIsComcam) {
      final comcam =
          region.where((group) => group.people.any(isComcam)).toList();
      if (comcam.isNotEmpty) {
        region.removeWhere((group) => group.people.any(isComcam));
        final merged = comcam.expand((group) => group.people).toList()
          ..sort(_personOrder);
        region.insert(
          0,
          CountryCityGroup(
            label: ComcamRegion.unifiedRegionLabel,
            people: merged,
            distanceKm: comcam
                .map((group) => group.distanceKm ?? double.infinity)
                .reduce((a, b) => a < b ? a : b),
          ),
        );
      }
    }

    final states = remaining.entries.map((entry) {
      final cities = entry.value.values.toList()
        ..sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      return CountrySubdivisionGroup(label: entry.key, cities: cities);
    }).toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    return PeopleCountryHierarchy(
        sameCity: sameCity,
        region: region,
        nearbyCities: nearby,
        remaining: states);
  }

  static int _personOrder(CountryPerson a, CountryPerson b) {
    if (a.online != b.online) return a.online ? -1 : 1;
    final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return name != 0 ? name : a.uid.compareTo(b.uid);
  }

  static String _cityKey(CountryPerson person) {
    final city = UserSearchNormalize.normalize(person.city);
    final state = UserSearchNormalize.normalize(person.subdivision);
    return '${person.countryCode.toLowerCase()}|$state|${city.isEmpty ? '—' : city}';
  }

  static String _subdivisionLabel(CountryPerson person) {
    final value = person.subdivision.trim();
    return value.isEmpty ? '—' : value;
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
