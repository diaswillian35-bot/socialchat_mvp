/// Diagnóstico seguro de presença (Profile/Release) — sem PII.
class PresenceDiagEvent {
  const PresenceDiagEvent({
    required this.code,
    required this.at,
    required this.role,
    this.fromPhase,
    this.toPhase,
    this.errorCategory,
    this.attempt,
    this.heartbeatAgeSec,
  });

  final String code;
  final DateTime at;
  final String role; // writer | reader
  final String? fromPhase;
  final String? toPhase;
  final String? errorCategory;
  final int? attempt;
  final int? heartbeatAgeSec;

  Map<String, Object?> toJson() => {
        'code': code,
        'at': at.toIso8601String(),
        'role': role,
        if (fromPhase != null) 'from': fromPhase,
        if (toPhase != null) 'to': toPhase,
        if (errorCategory != null) 'err': errorCategory,
        if (attempt != null) 'attempt': attempt,
        if (heartbeatAgeSec != null) 'hbAgeSec': heartbeatAgeSec,
      };

  @override
  String toString() =>
      'PresenceDiag[$role] $code from=$fromPhase to=$toPhase '
      'err=$errorCategory attempt=$attempt hbAge=$heartbeatAgeSec';
}

/// Ring buffer local dos últimos eventos (sem UID/token/email).
class PresenceDiagnostics {
  PresenceDiagnostics({this.maxEvents = 40});

  final int maxEvents;
  final List<PresenceDiagEvent> _events = [];

  List<PresenceDiagEvent> get events => List.unmodifiable(_events);

  void record(PresenceDiagEvent event) {
    _events.add(event);
    while (_events.length > maxEvents) {
      _events.removeAt(0);
    }
  }

  void clear() => _events.clear();

  static String sanitizeError(Object? error) {
    if (error == null) return 'unknown';
    final s = error.toString().toLowerCase();
    if (s.contains('permission-denied') ||
        s.contains('permission_denied') ||
        s.contains('permission denied')) {
      return 'permission_denied';
    }
    if (s.contains('network') || s.contains('socket') || s.contains('offline')) {
      return 'network';
    }
    if (s.contains('unauthenticated') || s.contains('token')) {
      return 'auth_token';
    }
    if (s.contains('auth')) return 'auth';
    if (s.contains('disconnected') || s.contains('disconnect')) {
      return 'disconnected';
    }
    if (s.contains('timeout')) return 'timeout';
    return 'transient';
  }
}
