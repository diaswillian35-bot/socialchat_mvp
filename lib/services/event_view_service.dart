import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Resultado da callable [registerEventView].
class EventViewRegistrationResult {
  const EventViewRegistrationResult({
    required this.countedUnique,
    required this.viewsCount,
    required this.totalOpensCount,
  });

  final bool countedUnique;
  final int viewsCount;
  final int totalOpensCount;

  factory EventViewRegistrationResult.fromMap(Map<dynamic, dynamic> data) {
    return EventViewRegistrationResult(
      countedUnique: data['countedUnique'] == true,
      viewsCount: _readInt(data['viewsCount']),
      totalOpensCount: _readInt(data['totalOpensCount']),
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}

/// Registra abertura da página pública do evento via Cloud Function.
class EventViewService {
  EventViewService._();

  static final EventViewService instance = EventViewService._();

  FirebaseFunctions get _functions {
    return FirebaseFunctions.instanceFor(region: 'us-central1');
  }

  Future<EventViewRegistrationResult?> registerView({
    required String eventId,
    required String source,
  }) async {
    try {
      final callable = _functions.httpsCallable('registerEventView');
      final result = await callable.call<Map<dynamic, dynamic>>({
        'eventId': eventId,
        'source': source,
      });

      return EventViewRegistrationResult.fromMap(result.data);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('registerEventView failed for $eventId: $error');
        debugPrint('$stackTrace');
      }
      return null;
    }
  }
}

/// Garante uma única chamada por abertura da página (ignora rebuilds).
class EventViewRegistrationGuard {
  String? _registeredEventId;

  Future<EventViewRegistrationResult?> registerOnce({
    required String eventId,
    required String source,
  }) async {
    if (_registeredEventId == eventId) {
      return null;
    }

    _registeredEventId = eventId;

    return EventViewService.instance.registerView(
      eventId: eventId,
      source: source,
    );
  }

  void reset() {
    _registeredEventId = null;
  }
}
