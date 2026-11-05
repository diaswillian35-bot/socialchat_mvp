import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/firestore_place_mapper.dart';
import 'package:socialchat_mvp/features/locais/data/place_submission_service.dart';
import 'package:socialchat_mvp/features/locais/logic/place_hours_logic.dart';
import 'package:socialchat_mvp/features/locais/models/place_listing.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// John Burger: qui, sex e sáb 15:00-21:00, Toronto (só delivery).
Map<String, dynamic> johnBurger({Map<String, dynamic>? extra}) => {
      'contractVersion': 'remdy.places.v1',
      'moderationStatus': 'published',
      'active': true,
      'deleted': false,
      'name': 'John Burger',
      'category': 'restaurant',
      'countryCode': 'CA',
      'stateName': 'Ontario',
      'cityName': 'Toronto',
      'deliveryOnly': true,
      'photoUrls': ['https://cdn.example.com/p.jpg'],
      'hours': PlaceHoursLogic.toJson([
        for (final d in [4, 5, 6])
          PlaceHours(weekday: d, opens: '15:00', closes: '21:00'),
      ]),
      ...?extra,
    };

PlaceListing parse(Map<String, dynamic> data) =>
    FirestorePlaceMapper.tryParse('jb', data)!;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('John Burger qui-sáb 15-21 em Toronto (EST, UTC-5)', () {
    final p = parse(johnBurger());

    test('fuso derivado de CA/Ontario', () {
      expect(p.effectiveTimeZone, 'America/Toronto');
    });
    test('quarta 22:36 ET fechado', () {
      expect(p.isOpenAt(DateTime.utc(2026, 11, 5, 3, 36)), isFalse);
    });
    test('quinta 12:00 ET fechado', () {
      expect(p.isOpenAt(DateTime.utc(2026, 11, 5, 17)), isFalse);
    });
    test('quinta 15:00 e 20:59 ET aberto; 21:00 fechado', () {
      expect(p.isOpenAt(DateTime.utc(2026, 11, 5, 20)), isTrue);
      expect(p.isOpenAt(DateTime.utc(2026, 11, 6, 1, 59)), isTrue);
      expect(p.isOpenAt(DateTime.utc(2026, 11, 6, 2)), isFalse);
    });
    test('domingo fechado', () {
      expect(p.isOpenAt(DateTime.utc(2026, 11, 8, 20)), isFalse);
    });
    test('aparelho em Brasília: vale o relógio de Toronto', () {
      // Quinta 15:30 em Brasília = 13:30 ET -> fechado.
      final brasilia = DateTime.utc(2026, 11, 5, 18, 30);
      expect(PlaceHoursLogic.localTime(brasilia, 'America/Sao_Paulo').hour, 15);
      expect(p.isOpenAt(brasilia), isFalse);
      // Quinta 18:00 em Brasília = 16:00 ET -> aberto.
      expect(p.isOpenAt(DateTime.utc(2026, 11, 5, 21)), isTrue);
      // Sábado 23:30 em Brasília = 21:30 ET -> fechado.
      expect(p.isOpenAt(DateTime.utc(2026, 11, 8, 2, 30)), isFalse);
    });
    test('timeZone gravado tem prioridade', () {
      final lx = parse(johnBurger(extra: {'timeZone': 'Europe/Lisbon'}));
      expect(lx.effectiveTimeZone, 'Europe/Lisbon');
      // Quinta 15:00 em Lisboa (UTC+0).
      expect(lx.isOpenAt(DateTime.utc(2026, 11, 5, 15)), isTrue);
    });
  });

  group('18:00-02:00 (passa da meia-noite)', () {
    final slots = [
      const PlaceHours(weekday: 5, opens: '18:00', closes: '02:00'),
    ];
    test('sexta 23:00 aberto, sábado 01:30 aberto, 02:00 fechado', () {
      expect(PlaceHoursLogic.isOpen(slots, DateTime(2026, 11, 6, 23)), isTrue);
      expect(
          PlaceHoursLogic.isOpen(slots, DateTime(2026, 11, 7, 1, 30)), isTrue);
      expect(PlaceHoursLogic.isOpen(slots, DateTime(2026, 11, 7, 2)), isFalse);
    });
    test('sexta 01:00 (madrugada de quinta) fechado; sábado 18:00 fechado', () {
      expect(PlaceHoursLogic.isOpen(slots, DateTime(2026, 11, 6, 1)), isFalse);
      expect(PlaceHoursLogic.isOpen(slots, DateTime(2026, 11, 7, 18)), isFalse);
    });
    test('domingo->segunda: madrugada de segunda conta', () {
      final sun = [
        const PlaceHours(weekday: 7, opens: '20:00', closes: '01:00'),
      ];
      expect(PlaceHoursLogic.isOpen(sun, DateTime(2026, 11, 9, 0, 30)), isTrue);
    });
  });

  group('texto antigo (hoursNote)', () {
    List<int> days(List<PlaceHours>? s) => s!.map((e) => e.weekday).toList();

    test('formato atual HH:MM-HH:MM = todos os dias', () {
      final s = PlaceHoursLogic.parseLegacy('08:00-20:00')!;
      expect(days(s), [1, 2, 3, 4, 5, 6, 7]);
      expect(s.first.opens, '08:00');
    });
    test('texto do John Burger (Dia: HH:MM – HH:MM, 7 linhas)', () {
      const note = 'Segunda: 08:00 – 20:00\nTerça: 08:00 – 20:00\n'
          'Quarta: 08:00 – 20:00\nQuinta: 08:00 – 20:00\n'
          'Sexta: 08:00 – 20:00\nSábado: 08:00 – 20:00\n'
          'Domingo: 08:00 – 20:00';
      final s = PlaceHoursLogic.parseLegacy(note)!;
      expect(days(s), [1, 2, 3, 4, 5, 6, 7]);
      expect(s.every((e) => e.opens == '08:00' && e.closes == '20:00'), isTrue);
    });
    test('en / es / fr / pt-PT', () {
      expect(
          days(PlaceHoursLogic.parseLegacy(
              'Thursday: 15:00 - 21:00\nFriday: 15:00 - 21:00\nSunday: closed')),
          [4, 5]);
      expect(days(PlaceHoursLogic.parseLegacy('Jueves: 15:00 – 21:00')), [4]);
      expect(days(PlaceHoursLogic.parseLegacy('Jeudi : 15h00 – 21h00')), [4]);
      expect(days(PlaceHoursLogic.parseLegacy('Sábado: 10:00 — 14:00')), [6]);
    });
    test('intervalo de dias e "11h às 23h"', () {
      final s = PlaceHoursLogic.parseLegacy('Seg a sex, 11h às 23h')!;
      expect(days(s), [1, 2, 3, 4, 5]);
      expect(s.first.closes, '23:00');
      expect(days(PlaceHoursLogic.parseLegacy('Sex a dom: 18:00-02:00')),
          [5, 6, 7]);
    });
    test('texto ilegível = nulo (mostra o texto)', () {
      expect(PlaceHoursLogic.parseLegacy('Ligue antes'), isNull);
      final p = parse(johnBurger(extra: {
        'hours': null,
        'hoursNote': 'Consulte pelo WhatsApp',
      }));
      expect(p.hours, isEmpty);
      expect(p.hoursUnknown, isTrue);
    });
    test('sem hours estruturado, o mapper lê o hoursNote', () {
      final p = parse(johnBurger(extra: {
        'hours': null,
        'hoursNote': 'Quinta: 15:00 – 21:00\nSexta: 15:00 – 21:00',
      }));
      expect(days(p.hours), [4, 5]);
      expect(p.hoursUnknown, isFalse);
    });
  });

  group('grupos do editor <-> dias', () {
    test('qui-sáb + dom: 2 grupos, ida e volta', () {
      final groups = [
        PlaceHoursGroup(days: {4, 5, 6}, opens: '15:00', closes: '21:00'),
        PlaceHoursGroup(days: {7}, opens: '12:00', closes: '18:00'),
      ];
      final slots = PlaceHoursLogic.fromGroups(groups);
      expect(slots.map((s) => s.weekday), [4, 5, 6, 7]);
      final back = PlaceHoursLogic.toGroups(slots);
      expect(back.length, 2);
      expect(back[0].days, {4, 5, 6});
      expect(back[0].opens, '15:00');
      expect(back[1].days, {7});
    });
    test('dia em dois grupos vale o primeiro; dias fora = fechado', () {
      final slots = PlaceHoursLogic.fromGroups([
        PlaceHoursGroup(days: {1, 2}, opens: '09:00', closes: '12:00'),
        PlaceHoursGroup(days: {2, 3}, opens: '14:00', closes: '18:00'),
      ]);
      expect(slots.map((s) => '${s.weekday} ${s.opens}'),
          ['1 09:00', '2 09:00', '3 14:00']);
    });
    test('grupo sem dias ou com horário igual é ignorado', () {
      expect(
          PlaceHoursLogic.fromGroups([
            PlaceHoursGroup(),
            PlaceHoursGroup(days: {1}, opens: '10:00', closes: '10:00'),
          ]),
          isEmpty);
    });
    test('JSON ida e volta', () {
      final slots = PlaceHoursLogic.fromGroups([
        PlaceHoursGroup(days: {5}, opens: '18:00', closes: '02:00'),
      ]);
      final json = PlaceHoursLogic.toJson(slots);
      expect((json['days'] as Map)['5'], [
        {'o': '18:00', 'c': '02:00'}
      ]);
      expect((json['days'] as Map)['1'], isEmpty);
      final back = PlaceHoursLogic.fromJson(json)!;
      expect(back.single.weekday, 5);
    });
  });

  group('PlaceDraft: hoursNote gerado para o backend atual', () {
    test('qui-sáb: uma linha por dia, legível pelo parser', () {
      final d = PlaceDraft(countryCode: 'CA', stateName: 'Ontario')
        ..hours = PlaceHoursLogic.fromGroups([
          PlaceHoursGroup(days: {4, 5, 6}, opens: '15:00', closes: '21:00'),
        ]);
      final f = d.toFields();
      expect(f['hoursNote'],
          'Qui: 15:00-21:00\nSex: 15:00-21:00\nSáb: 15:00-21:00');
      expect(f['timeZone'], 'America/Toronto');
      expect(days(PlaceHoursLogic.parseLegacy(f['hoursNote'] as String)),
          [4, 5, 6]);
    });
    test('todos os dias iguais: HH:MM-HH:MM', () {
      final d = PlaceDraft()
        ..hours = PlaceHoursLogic.fromGroups([
          PlaceHoursGroup(
              days: {1, 2, 3, 4, 5, 6, 7}, opens: '08:00', closes: '20:00'),
        ]);
      expect(d.toFields()['hoursNote'], '08:00-20:00');
    });
    test('sem horário estruturado mantém o texto antigo', () {
      final d = PlaceDraft(hoursNote: 'Ligue antes');
      expect(d.toFields()['hoursNote'], 'Ligue antes');
    });
    test('fromSummary lê hours ou o texto antigo', () {
      final d = PlaceDraft.fromSummary({
        'hoursNote': 'Quinta: 15:00 – 21:00',
      });
      expect(d.hours.single.weekday, 4);
    });
  });
}

List<int> days(List<PlaceHours>? s) => s!.map((e) => e.weekday).toList();
