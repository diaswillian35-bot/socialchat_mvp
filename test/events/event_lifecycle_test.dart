import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/utils/event_lifecycle.dart';

void main() {
  final now = DateTime.utc(2026, 7, 31, 15, 0);

  group('EventLifecycle.classify', () {
    test('futuro: startAt > agora', () {
      final b = EventLifecycle.classify(
        nowUtc: now,
        startAtUtc: now.add(const Duration(hours: 1)),
        endAtUtc: now.add(const Duration(hours: 3)),
      );
      expect(b, EventLifecycleBucket.upcoming);
    });

    test('começando agora: startAt == agora', () {
      final b = EventLifecycle.classify(
        nowUtc: now,
        startAtUtc: now,
        endAtUtc: now.add(const Duration(hours: 2)),
      );
      expect(b, EventLifecycleBucket.live);
    });

    test('em andamento', () {
      final b = EventLifecycle.classify(
        nowUtc: now,
        startAtUtc: now.subtract(const Duration(hours: 1)),
        endAtUtc: now.add(const Duration(hours: 1)),
      );
      expect(b, EventLifecycleBucket.live);
    });

    test('terminando agora: endAt == agora', () {
      final b = EventLifecycle.classify(
        nowUtc: now,
        startAtUtc: now.subtract(const Duration(hours: 2)),
        endAtUtc: now,
      );
      expect(b, EventLifecycleBucket.live);
    });

    test('passado: endAt < agora', () {
      final b = EventLifecycle.classify(
        nowUtc: now,
        startAtUtc: now.subtract(const Duration(days: 2)),
        endAtUtc: now.subtract(const Duration(hours: 1)),
      );
      expect(b, EventLifecycleBucket.past);
    });

    test('múltiplos dias em andamento', () {
      final b = EventLifecycle.classify(
        nowUtc: now,
        startAtUtc: now.subtract(const Duration(days: 2)),
        endAtUtc: now.add(const Duration(days: 3)),
      );
      expect(b, EventLifecycleBucket.live);
    });

    test('arquivado tem prioridade', () {
      final b = EventLifecycle.classify(
        nowUtc: now,
        startAtUtc: now.add(const Duration(days: 1)),
        endAtUtc: now.add(const Duration(days: 1, hours: 2)),
        archived: true,
      );
      expect(b, EventLifecycleBucket.archived);
    });

    test('sem endAt não inventa duração', () {
      final b = EventLifecycle.classify(
        nowUtc: now,
        startAtUtc: now.subtract(const Duration(hours: 1)),
        endAtUtc: null,
      );
      expect(b, EventLifecycleBucket.unknown);
    });

    test('legado missing endAt detectado', () {
      final data = <String, dynamic>{
        'startAt': now.subtract(const Duration(days: 1)),
      };
      expect(EventLifecycle.isLegacyMissingEndAt(data, nowUtc: now), isTrue);
    });
  });

  group('passesPublicVisibility', () {
    test('bloqueia cancelado/apagado/rejeitado/pendente/inativo/arquivado', () {
      expect(
        EventLifecycle.passesPublicVisibility({
          'status': 'approved',
          'isActive': true,
        }),
        isTrue,
      );
      expect(
        EventLifecycle.passesPublicVisibility({
          'status': 'cancelled',
          'isActive': true,
        }),
        isFalse,
      );
      expect(
        EventLifecycle.passesPublicVisibility({
          'status': 'approved',
          'isActive': true,
          'deleted': true,
        }),
        isFalse,
      );
      expect(
        EventLifecycle.passesPublicVisibility({
          'status': 'rejected',
          'isActive': true,
        }),
        isFalse,
      );
      expect(
        EventLifecycle.passesPublicVisibility({
          'status': 'pending',
          'isActive': true,
        }),
        isFalse,
      );
      expect(
        EventLifecycle.passesPublicVisibility({
          'status': 'approved',
          'isActive': false,
        }),
        isFalse,
      );
      expect(
        EventLifecycle.passesPublicVisibility({
          'status': 'approved',
          'isActive': true,
          'archived': true,
        }),
        isFalse,
      );
    });
  });
}
