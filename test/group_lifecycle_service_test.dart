import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/group_lifecycle_service.dart';

void main() {
  group('GroupLifecycleService error keys', () {
    test('leave owner failed-precondition', () {
      final e = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Owner cannot leave the group.',
      );
      expect(
        GroupLifecycleService.leaveErrorKey(e),
        'group_owner_cannot_leave',
      );
    });

    test('transfer permission-denied', () {
      final e = FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Only owner can transfer ownership.',
      );
      expect(
        GroupLifecycleService.transferErrorKey(e),
        'group_transfer_no_permission',
      );
    });

    test('transfer failed-precondition', () {
      final e = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'New owner must be a member.',
      );
      expect(
        GroupLifecycleService.transferErrorKey(e),
        'group_transfer_invalid',
      );
    });
  });
}
