import 'report_category.dart';

class BlockUserOutcome {
  const BlockUserOutcome({
    required this.applied,
    required this.newlyBlocked,
    required this.reportWritten,
    this.reportError,
  });

  static const ignored = BlockUserOutcome(
    applied: false,
    newlyBlocked: false,
    reportWritten: false,
  );

  static const alreadyBlocked = BlockUserOutcome(
    applied: true,
    newlyBlocked: false,
    reportWritten: false,
  );

  final bool applied;
  final bool newlyBlocked;
  final bool reportWritten;
  final Object? reportError;

  bool get shouldWarnReportFailure => newlyBlocked && !reportWritten;
}

/// Pure helpers for block → existing `reports` collection (no parallel store).
class BlockReportLogic {
  BlockReportLogic._();

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
    'imageUrl',
    'audioUrl',
    'displayName',
  };

  static List<String> blockedUids(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  static bool shouldCreateBlockReport({
    required String? actorUid,
    required String targetUid,
    required List<String> currentlyBlocked,
  }) {
    if (actorUid == null || actorUid.isEmpty) return false;
    if (targetUid.isEmpty || targetUid == actorUid) return false;
    return !currentlyBlocked.contains(targetUid);
  }

  /// Fields accepted by current reports rules (`create if signedIn()`).
  /// Admin SDK readers already key off fromUid / reporterUid / reportedUid.
  static Map<String, Object> reportFields({
    required String actorUid,
    required String targetUid,
  }) {
    final category = ReportCategory.userBlocked;
    return {
      'fromUid': actorUid,
      'reporterUid': actorUid,
      'reportedUid': targetUid,
      'reason': category.code,
      ...reportClassification(category),
      'status': 'open',
      'contextType': 'block',
      'source': 'block_service',
    };
  }

  static Future<BlockUserOutcome> afterNewBlockWriteReport({
    required String actorUid,
    required String targetUid,
    required Future<void> Function(Map<String, Object> fields) persistReport,
  }) async {
    try {
      await persistReport(
        reportFields(actorUid: actorUid, targetUid: targetUid),
      );
      return const BlockUserOutcome(
        applied: true,
        newlyBlocked: true,
        reportWritten: true,
      );
    } catch (e) {
      return BlockUserOutcome(
        applied: true,
        newlyBlocked: true,
        reportWritten: false,
        reportError: e,
      );
    }
  }
}
