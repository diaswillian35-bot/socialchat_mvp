import 'dart:math';

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
      countedUnique:
          data['countedUnique'] == true || data['counted'] == true,
      viewsCount: _readInt(data['viewsCount']),
      totalOpensCount: _readInt(
        data['totalOpensCount'] ?? data['viewsCount'],
      ),
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}

/// Registra abertura da página do evento via Cloud Function.
class EventViewService {
  EventViewService._();

  static final EventViewService instance = EventViewService._();

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  String _newSessionId() {
    final ms = DateTime.now().microsecondsSinceEpoch;
    final r = Random().nextInt(1 << 32);
    return 'v_${ms}_$r';
  }

  Future<EventViewRegistrationResult?> registerView({
    required String eventId,
    String source = 'mobile_app',
  }) async {
    try {
      final callable = _functions.httpsCallable('registerEventView');
      final result = await callable.call(<String, dynamic>{
        'eventId': eventId,
        'viewerSessionId': _newSessionId(),
        'source': source,
      });
      final data = result.data;
      if (data is Map) {
        return EventViewRegistrationResult.fromMap(data);
      }
      return null;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('registerEventView failed for $eventId: $error');
        debugPrint('$stackTrace');
      }
      // Falha de analytics não bloqueia a abertura do evento.
      return null;
    }
  }
}

/// Garante uma única chamada por abertura da página (ignora rebuilds).
class EventViewRegistrationGuard {
  String? _registeredEventId;

  Future<EventViewRegistrationResult?> registerOnce({
    required String eventId,
    String source = 'mobile_app',
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
