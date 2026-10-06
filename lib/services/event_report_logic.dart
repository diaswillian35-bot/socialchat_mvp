import 'report_category.dart';

/// Event / event-comment reports into the existing `reports` collection.
class EventReportLogic {
  EventReportLogic._();

  static const contextEvent = 'event';
  static const contextComment = 'event_comment';
  static const sourceEventDetail = 'event_detail';

  static const categories = <ReportCategory>[
    ReportCategory.childSafety,
    ReportCategory.inappropriate,
    ReportCategory.spam,
    ReportCategory.harassment,
    ReportCategory.threat,
    ReportCategory.other,
  ];

  static const allowedReportKeys = <String>{
    'fromUid',
    'reporterUid',
    'reportedUid',
    'reason',
    'reasonCode',
    'priority',
    'status',
    'contextType',
    'source',
    'eventId',
    'commentId',
    'snapshot',
    'requiresChildSafetyReview',
  };

  static const forbiddenPiiKeys = <String>{
    'email',
    'phone',
    'phoneNumber',
    'dateOfBirth',
    'birthDate',
    'text',
    'message',
    'messageText',
    'title',
    'description',
    'imageUrl',
    'audioUrl',
    'photoUrl',
    'displayName',
    'name',
  };

  static bool canReportEvent({
    required String? reporterUid,
    required String organizerUid,
  }) {
    final me = (reporterUid ?? '').trim();
    final org = organizerUid.trim();
    if (me.isEmpty || org.isEmpty) return false;
    return me != org;
  }

  static bool canReportComment({
    required String? reporterUid,
    required String authorUid,
    required String commentId,
  }) {
    final me = (reporterUid ?? '').trim();
    final author = authorUid.trim();
    final id = commentId.trim();
    if (me.isEmpty || author.isEmpty || id.isEmpty) return false;
    return me != author;
  }

  static bool shouldPersist({
    required bool confirmed,
    required bool inFlight,
  }) =>
      confirmed && !inFlight;

  static Map<String, Object> reportFields({
    required String reporterUid,
    required String reportedUid,
    required ReportCategory category,
    required String reasonLabel,
    required String eventId,
    String? commentId,
  }) {
    final event = eventId.trim();
    final comment = (commentId ?? '').trim();
    final isComment = comment.isNotEmpty;
    final snapshot = <String, Object>{
      'eventId': event,
      if (isComment) 'commentId': comment,
    };
    return {
      'fromUid': reporterUid,
      'reporterUid': reporterUid,
      'reportedUid': reportedUid.trim(),
      'reason': reasonLabel,
      ...reportClassification(category),
      'status': 'open',
      'contextType': isComment ? contextComment : contextEvent,
      'source': sourceEventDetail,
      'eventId': event,
      if (isComment) 'commentId': comment,
      'snapshot': snapshot,
    };
  }

  static bool payloadIsSafe(Map<String, Object> fields) {
    if (fields.keys.any(forbiddenPiiKeys.contains)) return false;
    final extra = fields.keys.where((k) => !allowedReportKeys.contains(k));
    if (extra.isNotEmpty) return false;
    final snap = fields['snapshot'];
    if (snap is Map) {
      if (snap.keys.any(forbiddenPiiKeys.contains)) return false;
      if (snap.containsKey('text') || snap.containsKey('title')) return false;
    }
    return true;
  }
}
