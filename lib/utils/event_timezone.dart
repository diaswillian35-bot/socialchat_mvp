/// Conversão de horário de parede (local do evento) ↔ UTC com IANA.
import 'package:timezone/timezone.dart' as tz;

class EventTimezone {
  EventTimezone._();

  static bool _ready = false;

  static bool get isReady => _ready;

  /// Locais comuns oferecidos no seletor.
  static const suggestedZones = <String>[
    'America/Toronto',
    'America/Sao_Paulo',
    'America/New_York',
    'America/Mexico_City',
    'Europe/Lisbon',
    'Europe/London',
    'Europe/Paris',
    'UTC',
  ];

  static final RegExp _ianaRe = RegExp(
    r'^(?:UTC|[A-Za-z_]+/(?:[A-Za-z0-9_+-]+(?:/[A-Za-z0-9_+-]+)?))$',
  );

  static bool isValidIana(String zone) {
    final z = zone.trim();
    if (z.isEmpty || z.length > 64) return false;
    if (!_ianaRe.hasMatch(z)) return false;
    if (!_ready) return true;
    try {
      tz.getLocation(z);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Marca o banco tz como carregado (após `tz.initializeTimeZones()`).
  static void markReady() {
    _ready = true;
  }

  /// Converte parede civil no [timeZone] para instante UTC.
  static DateTime wallToUtc({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
    required String timeZone,
  }) {
    final zone = timeZone.trim();
    if (!isValidIana(zone)) {
      throw ArgumentError('invalid_event_timezone');
    }
    if (_ready) {
      final loc = tz.getLocation(zone);
      final local = tz.TZDateTime(loc, year, month, day, hour, minute);
      return local.toUtc();
    }
    return DateTime(year, month, day, hour, minute).toUtc();
  }

  /// Sugestão de término para evento de um dia: +2h no mesmo fuso.
  static DateTime suggestSameDayEndUtc({
    required DateTime startUtc,
    required String timeZone,
  }) {
    final zone = timeZone.trim();
    if (_ready && isValidIana(zone)) {
      final loc = tz.getLocation(zone);
      final localStart = tz.TZDateTime.from(startUtc.toUtc(), loc);
      final localEnd = localStart.add(const Duration(hours: 2));
      return localEnd.toUtc();
    }
    return startUtc.toUtc().add(const Duration(hours: 2));
  }

  static void assertEndAfterStart({
    required DateTime startUtc,
    required DateTime endUtc,
  }) {
    if (!endUtc.toUtc().isAfter(startUtc.toUtc())) {
      throw ArgumentError('end_before_start');
    }
  }
}
