import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:socialchat_mvp/utils/event_timezone.dart';

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    EventTimezone.markReady();
  });

  test('IANA válidos', () {
    expect(EventTimezone.isValidIana('America/Toronto'), isTrue);
    expect(EventTimezone.isValidIana('America/Sao_Paulo'), isTrue);
    expect(EventTimezone.isValidIana('Europe/Lisbon'), isTrue);
    expect(EventTimezone.isValidIana('not a zone'), isFalse);
  });

  test('parede Toronto → UTC (inverno EST)', () {
    // 2026-01-15 19:00 America/Toronto = 00:00 UTC do dia 16
    final utc = EventTimezone.wallToUtc(
      year: 2026,
      month: 1,
      day: 15,
      hour: 19,
      minute: 0,
      timeZone: 'America/Toronto',
    );
    expect(utc.isUtc, isTrue);
    expect(utc.hour, 0);
    expect(utc.day, 16);
  });

  test('DST Toronto: primavera 2026-03-08', () {
    // 2026-03-08 2:00 não existe; 1:30 EST = 6:30 UTC; 3:00 EDT = 7:00 UTC
    final before = EventTimezone.wallToUtc(
      year: 2026,
      month: 3,
      day: 8,
      hour: 1,
      minute: 30,
      timeZone: 'America/Toronto',
    );
    final after = EventTimezone.wallToUtc(
      year: 2026,
      month: 3,
      day: 8,
      hour: 3,
      minute: 0,
      timeZone: 'America/Toronto',
    );
    expect(before.toUtc(), DateTime.utc(2026, 3, 8, 6, 30));
    expect(after.toUtc(), DateTime.utc(2026, 3, 8, 7, 0));
  });

  test('end deve ser após start', () {
    final start = DateTime.utc(2026, 7, 1, 18);
    expect(
      () => EventTimezone.assertEndAfterStart(
        startUtc: start,
        endUtc: start,
      ),
      throwsArgumentError,
    );
  });

  test('sugestão same-day +2h no fuso', () {
    final start = EventTimezone.wallToUtc(
      year: 2026,
      month: 7,
      day: 10,
      hour: 19,
      minute: 0,
      timeZone: 'America/Sao_Paulo',
    );
    final end = EventTimezone.suggestSameDayEndUtc(
      startUtc: start,
      timeZone: 'America/Sao_Paulo',
    );
    final loc = tz.getLocation('America/Sao_Paulo');
    final localEnd = tz.TZDateTime.from(end, loc);
    expect(localEnd.hour, 21);
  });
}
