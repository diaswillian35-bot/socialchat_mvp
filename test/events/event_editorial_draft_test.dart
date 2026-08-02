import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/models/event_editorial_draft.dart';
import 'package:socialchat_mvp/models/event_presentation.dart';

void main() {
  group('EventEditorialDraft validation', () {
    EventEditorialDraft baseOk() {
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      final day = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
      return EventEditorialDraft(
        title: 'Festival Test',
        description: 'A full description of the event for validation.',
        category: 'Festival',
        startDate: day,
        startTime: '19:00',
        endDate: day,
        endTime: '22:00',
        eventTimeZone: 'America/Toronto',
        city: 'Toronto',
        cityKey: 'toronto',
        placeName: 'Harbourfront',
        countryCode: 'ca',
        ticketType: 'free',
        isFree: true,
      );
    }

    test('step 0 requires title description category', () {
      final empty = const EventEditorialDraft();
      expect(empty.validateStep(0), 'create_event_required_title');

      final withTitle = empty.copyWith(title: 'Hi');
      expect(withTitle.validateStep(0), 'create_event_required_description');

      final okInfo = withTitle.copyWith(
        description: 'Long enough description',
        category: 'Show',
      );
      expect(okInfo.validateStep(0), isNull);
    });

    test('step 1 requires dates place and country', () {
      final d = baseOk().copyWith(
        startDate: null,
        startTime: '',
      );
      expect(d.validateStep(1), 'events_start_required');

      final noPlace = baseOk().copyWith(placeName: '');
      expect(noPlace.validateStep(1), 'event_wizard_place_required');

      expect(baseOk().validateStep(1), isNull);
    });

    test('ticket types free paid inquire', () {
      final free = baseOk().withTicketType('free');
      expect(free.ticketType, 'free');
      expect(free.isFree, isTrue);
      expect(free.validateStep(2), isNull);

      final paidNoPrice = baseOk().withTicketType('paid');
      expect(paidNoPrice.isFree, isFalse);
      expect(paidNoPrice.validateStep(2), 'event_wizard_price_required');

      final paid = paidNoPrice.copyWith(price: '40', priceCurrency: 'CAD');
      expect(paid.validateStep(2), isNull);

      final inquire = baseOk().withTicketType('inquire');
      expect(inquire.isFree, isFalse);
      expect(inquire.validateStep(2), isNull);
    });

    test('schedule order normalized in payload', () {
      final d = baseOk().copyWith(
        schedule: const [
          EventScheduleItem(id: 'b', title: 'Second', order: 5),
          EventScheduleItem(id: 'a', title: 'First', order: 1),
        ],
      );
      expect(d.validateStep(4), isNull);
      final payload = d.toCreateCallablePayload();
      final schedule = payload['schedule'] as List;
      expect(schedule.length, 2);
      expect(schedule[0]['title'], 'First');
      expect(schedule[0]['order'], 0);
      expect(schedule[1]['title'], 'Second');
      expect(schedule[1]['order'], 1);
    });

    test('public contact requires consent', () {
      final d = baseOk().copyWith(
        publicContact: 'hello@example.com',
        publicContactConsent: false,
      );
      expect(d.validateStep(5), 'event_wizard_contact_consent_required');
      expect(
        d.copyWith(publicContactConsent: true).validateStep(5),
        isNull,
      );
    });

    test('toCreateCallablePayload includes editorial fields', () {
      final d = baseOk().copyWith(
        shortDescription: 'Short',
        accessibility: 'Ramp',
        attractions: const [
          EventAttractionItem(id: '1', name: 'DJ', description: 'Live', order: 2),
        ],
      );
      final p = d.toCreateCallablePayload();
      expect(p['title'], 'Festival Test');
      expect(p.containsKey('startAtMs'), isTrue);
      expect(p.containsKey('endAtMs'), isTrue);
      expect(p['ticketType'], 'free');
      expect(p['isFree'], isTrue);
      expect(p['accessibility'], 'Ramp');
      final attr = p['attractions'] as List;
      expect(attr.first['order'], 0);
      expect(attr.first['name'], 'DJ');
    });
  });

  group('EventPresentation structured schedule/attractions', () {
    test('formats map schedule and attractions', () {
      final e = EventPresentation.fromMap('x', {
        'title': 'T',
        'schedule': [
          {
            'day': 'Fri',
            'startTime': '19:00',
            'endTime': '20:00',
            'title': 'Opening',
            'description': 'Gates open',
          },
        ],
        'attractions': [
          {'name': 'Band A', 'description': 'Rock set'},
          'Legacy string act',
        ],
      });
      expect(e.scheduleItems.first, contains('Fri'));
      expect(e.scheduleItems.first, contains('19:00–20:00'));
      expect(e.scheduleItems.first, contains('Opening'));
      expect(e.attractions.first, 'Band A — Rock set');
      expect(e.attractions.last, 'Legacy string act');
    });
  });
}
