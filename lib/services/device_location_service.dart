import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'group_location_normalize.dart';
import 'group_nearby_logic.dart';
import 'group_state_codes.dart';

/// Estado da permissão de localização, sem abrir aviso nenhum.
enum DeviceLocationAccess {
  /// Nunca perguntado (ou o Android permite perguntar de novo).
  notAsked,
  granted,
  denied,
  deniedForever,
  serviceOff,
}

/// Resultado do GPS + geocoder do aparelho. Só fica em memória.
class DeviceLocationFix {
  const DeviceLocationFix({
    required this.latitude,
    required this.longitude,
    this.countryCode = '',
    this.cityName = '',
    this.stateCode = '',
  });

  final double latitude;
  final double longitude;
  final String countryCode;
  final String cityName;
  final String stateCode;
}

/// O que a aba mostra acima da lista.
enum NearbyBanner {
  /// Nenhum aviso (GPS em uso, ou sem cidade alguma).
  none,

  /// Cartão "Ver grupos perto de você" (primeira vez).
  prompt,

  /// Linha "Mostrando grupos perto de {cidade do perfil}" + "Ativar localização".
  usingProfile,

  /// Fora do país de cadastro: GPS ignorado, perfil em uso.
  abroad,
}

class NearbyResolution {
  const NearbyResolution({required this.viewer, required this.banner});

  final NearbyViewer viewer;
  final NearbyBanner banner;
}

/// Decisão pura (testável) de qual localização usar e qual aviso mostrar.
class NearbyLocationDecision {
  NearbyLocationDecision._();

  static NearbyResolution decide({
    required NearbyViewer profile,
    required DeviceLocationAccess access,
    required bool snoozed,
    DeviceLocationFix? fix,
    bool adminOtherCountry = false,
  }) {
    // Modo admin com outro país: sem cidade nem GPS.
    if (adminOtherCountry) {
      return NearbyResolution(viewer: profile, banner: NearbyBanner.none);
    }
    final home = GroupLocationNormalize.countryCode(profile.countryCode);
    final hasProfileCity =
        profile.cityLabel.isNotEmpty || profile.cityKey.isNotEmpty;

    if (access == DeviceLocationAccess.granted && fix != null) {
      final gpsCountry = GroupLocationNormalize.countryCode(fix.countryCode);
      if (gpsCountry.isNotEmpty && gpsCountry == home) {
        final stateCode = fix.stateCode.isNotEmpty
            ? fix.stateCode
            : profile.stateCode;
        final viewer = NearbyViewer(
          countryCode: home,
          cityKey: GroupLocationNormalize.cityKey(fix.cityName),
          latitude: fix.latitude,
          longitude: fix.longitude,
          stateCode: stateCode,
          cityLabel: fix.cityName,
          source: NearbyLocationSource.gps,
        );
        return NearbyResolution(viewer: viewer, banner: NearbyBanner.none);
      }
      if (gpsCountry.isNotEmpty && gpsCountry != home) {
        return NearbyResolution(
          viewer: profile,
          banner: hasProfileCity ? NearbyBanner.abroad : NearbyBanner.none,
        );
      }
      // Geocoder falhou (sem internet): fica com o perfil, sem aviso.
      return NearbyResolution(viewer: profile, banner: NearbyBanner.none);
    }

    if (access == DeviceLocationAccess.granted) {
      return NearbyResolution(viewer: profile, banner: NearbyBanner.none);
    }

    if (access == DeviceLocationAccess.notAsked && !snoozed) {
      return NearbyResolution(viewer: profile, banner: NearbyBanner.prompt);
    }
    return NearbyResolution(
      viewer: profile,
      banner: hasProfileCity ? NearbyBanner.usingProfile : NearbyBanner.none,
    );
  }
}

/// Localização do aparelho só para ordenar "Perto de você".
///
/// - Precisão baixa (aproximada basta); nada é gravado no Firestore nem
///   enviado às functions. A posição fica só na memória desta sessão.
/// - O aviso do sistema só aparece em [requestAccess], chamado pelo botão
///   "Usar minha localização" / "Ativar localização".
class DeviceLocationService {
  DeviceLocationService._();

  static final DeviceLocationService instance = DeviceLocationService._();

  static const String _snoozeKey = 'groups_nearby_location_snooze_until';
  static const String _askedKey = 'groups_nearby_location_asked';
  static const Duration snoozeFor = Duration(days: 30);

  DeviceLocationFix? _cached;
  DateTime? _cachedAt;

  Future<bool> isSnoozed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getInt(_snoozeKey) ?? 0;
      return DateTime.now().millisecondsSinceEpoch < until;
    } catch (_) {
      return false;
    }
  }

  Future<void> snooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _snoozeKey,
        DateTime.now().add(snoozeFor).millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  Future<bool> _askedBefore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_askedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Lê o estado sem abrir aviso.
  Future<DeviceLocationAccess> access() async {
    try {
      final permission = await Geolocator.checkPermission();
      switch (permission) {
        case LocationPermission.always:
        case LocationPermission.whileInUse:
          final on = await Geolocator.isLocationServiceEnabled();
          return on
              ? DeviceLocationAccess.granted
              : DeviceLocationAccess.serviceOff;
        case LocationPermission.deniedForever:
          return DeviceLocationAccess.deniedForever;
        case LocationPermission.denied:
        case LocationPermission.unableToDetermine:
          return await _askedBefore()
              ? DeviceLocationAccess.denied
              : DeviceLocationAccess.notAsked;
      }
    } catch (_) {
      return DeviceLocationAccess.denied;
    }
  }

  /// Toque do usuário: pede a permissão (ou abre os Ajustes se já negou de vez).
  Future<DeviceLocationAccess> requestAccess() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_askedKey, true);
      await prefs.remove(_snoozeKey);
    } catch (_) {}
    final current = await access();
    if (current == DeviceLocationAccess.deniedForever) {
      await Geolocator.openAppSettings();
      return current;
    }
    if (current == DeviceLocationAccess.serviceOff) {
      await Geolocator.openLocationSettings();
      return current;
    }
    try {
      final p = await Geolocator.requestPermission();
      if (p == LocationPermission.deniedForever) {
        return DeviceLocationAccess.deniedForever;
      }
      if (p == LocationPermission.denied) return DeviceLocationAccess.denied;
    } catch (_) {
      return DeviceLocationAccess.denied;
    }
    return access();
  }

  /// Posição aproximada + cidade/estado/país pelo geocoder do aparelho.
  /// Cache de 10 min em memória. Null quando não dá.
  Future<DeviceLocationFix?> currentFix() async {
    final at = _cachedAt;
    if (_cached != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 10)) {
      return _cached;
    }
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {
        pos = null;
      }
    }
    if (pos == null) return null;

    var country = '';
    var city = '';
    var state = '';
    try {
      final marks = await geo.placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (marks.isNotEmpty) {
        final m = marks.first;
        country = (m.isoCountryCode ?? '').toLowerCase();
        city = (m.locality ?? '').trim();
        if (city.isEmpty) city = (m.subAdministrativeArea ?? '').trim();
        state = GroupStateCodes.normalize(country, m.administrativeArea);
      }
    } catch (_) {}

    final fix = DeviceLocationFix(
      latitude: pos.latitude,
      longitude: pos.longitude,
      countryCode: country,
      cityName: city,
      stateCode: state,
    );
    _cached = fix;
    _cachedAt = DateTime.now();
    return fix;
  }
}
