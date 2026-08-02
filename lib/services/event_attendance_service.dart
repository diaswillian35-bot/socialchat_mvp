import 'package:cloud_functions/cloud_functions.dart';

/// Participação segura em eventos via Cloud Functions.
class EventAttendanceService {
  EventAttendanceService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<Map<String, dynamic>> joinEvent({
    required String eventId,
  }) async {
    final callable = _functions.httpsCallable('joinEvent');
    final result = await callable.call(<String, dynamic>{
      'eventId': eventId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<Map<String, dynamic>> leaveEvent({
    required String eventId,
  }) async {
    final callable = _functions.httpsCallable('leaveEvent');
    final result = await callable.call(<String, dynamic>{
      'eventId': eventId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  static String joinErrorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'event_detail_login_to_join';
      case 'failed-precondition':
        final msg = (e.message ?? '').toLowerCase();
        if (msg.contains('no longer accepts') || msg.contains('attendees')) {
          return 'event_attendance_not_accepted';
        }
        return 'event_attendance_unavailable';
      case 'not-found':
        return 'event_attendance_unavailable';
      case 'permission-denied':
        return 'event_detail_join_error';
      default:
        return 'event_detail_join_error';
    }
  }

  static String leaveErrorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return 'event_attendance_unavailable';
      default:
        return 'event_detail_leave_error';
    }
  }
}
