/// Classificação canônica de eventos por timestamps UTC.
///
/// Regras oficiais (sem Function agendada):
/// - Futuros: startAt > agora
/// - Acontecendo agora: startAt <= agora && endAt >= agora
/// - Passados: endAt < agora
/// - Arquivados: archived == true (Meus eventos; prioridade de listagem)
enum EventLifecycleBucket {
  upcoming,
  live,
  past,
  archived,
  unknown,
}

class EventLifecycle {
  EventLifecycle._();

  static const pageSize = 20;
  static const publicPageSize = 50;

  /// Status permitidos na lista pública clássica.
  static const publicAllowedStatuses = {'approved'};

  /// Status que nunca devem aparecer na lista pública.
  static const publicBlockedStatuses = {
    'pending',
    'rejected',
    'cancelled',
    'canceled',
    'draft',
    // portal "published" — normalizar em backfill antes de misturar na query
    'published',
  };

  static DateTime? asUtcDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    try {
      final dynamic v = value;
      if (v.toDate is Function) {
        final DateTime d = v.toDate() as DateTime;
        return d.toUtc();
      }
    } catch (_) {}
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return null;
  }

  static bool isArchived(Map<String, dynamic> data) => data['archived'] == true;

  static bool isDeleted(Map<String, dynamic> data) => data['deleted'] == true;

  static bool isActiveFlag(Map<String, dynamic> data) => data['isActive'] == true;

  static String? statusOf(Map<String, dynamic> data) {
    final raw = data['status'];
    if (raw == null) return null;
    final s = raw.toString().trim().toLowerCase();
    return s.isEmpty ? null : s;
  }

  /// Visibilidade pública estrita (além da query).
  static bool passesPublicVisibility(Map<String, dynamic> data) {
    if (isDeleted(data)) return false;
    if (isArchived(data)) return false;
    if (!isActiveFlag(data)) return false;
    final status = statusOf(data);
    if (status == null) return false;
    if (!publicAllowedStatuses.contains(status)) return false;
    return true;
  }

  /// Classifica por data. [archived] tem prioridade quando [preferArchived] é true.
  static EventLifecycleBucket classify({
    required DateTime nowUtc,
    DateTime? startAtUtc,
    DateTime? endAtUtc,
    bool archived = false,
    bool preferArchived = true,
  }) {
    if (preferArchived && archived) return EventLifecycleBucket.archived;
    if (startAtUtc == null) return EventLifecycleBucket.unknown;
    final now = nowUtc.toUtc();
    final start = startAtUtc.toUtc();

    if (start.isAfter(now)) return EventLifecycleBucket.upcoming;

    if (endAtUtc != null) {
      final end = endAtUtc.toUtc();
      if (!end.isBefore(now)) {
        return EventLifecycleBucket.live;
      }
      return EventLifecycleBucket.past;
    }

    // Sem endAt: não inventar duração.
    return EventLifecycleBucket.unknown;
  }

  static EventLifecycleBucket classifyFromData(
    Map<String, dynamic> data, {
    DateTime? nowUtc,
    bool preferArchived = true,
  }) {
    return classify(
      nowUtc: (nowUtc ?? DateTime.now().toUtc()),
      startAtUtc: asUtcDateTime(data['startAt']),
      endAtUtc: asUtcDateTime(data['endAt']),
      archived: isArchived(data),
      preferArchived: preferArchived,
    );
  }

  /// Antigos sem endAt que já começaram — não sumir silenciosamente.
  static bool isLegacyMissingEndAt(
    Map<String, dynamic> data, {
    DateTime? nowUtc,
  }) {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final start = asUtcDateTime(data['startAt']);
    final end = asUtcDateTime(data['endAt']);
    if (start == null || end != null) return false;
    return !start.isAfter(now);
  }
}
