import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/event_management_service.dart';

void main() {
  group('EventManagementService.cancelErrorKey', () {
    test('permission-denied', () {
      final e = FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Only organizer can cancel.',
      );
      expect(
        EventManagementService.cancelErrorKey(e),
        'event_management_no_permission',
      );
    });

    test('not-found / failed-precondition', () {
      expect(
        EventManagementService.cancelErrorKey(
          FirebaseFunctionsException(code: 'not-found', message: 'x'),
        ),
        'event_management_unavailable',
      );
      expect(
        EventManagementService.cancelErrorKey(
          FirebaseFunctionsException(code: 'failed-precondition', message: 'x'),
        ),
        'event_management_unavailable',
      );
    });
  });
}
