class ReportCategory {
  const ReportCategory({
    required this.code,
    required this.labelKey,
    this.priority = 'normal',
  });

  final String code;
  final String labelKey;
  final String priority;

  bool get isChildSafety => code == childSafety.code;

  static const childSafety = ReportCategory(
    code: 'child_sexual_exploitation_or_abuse',
    labelKey: 'report_reason_child_sexual_exploitation',
    priority: 'critical',
  );

  static const inappropriate = ReportCategory(
    code: 'inappropriate_content',
    labelKey: 'report_reason_inappropriate',
  );

  static const spam = ReportCategory(
    code: 'spam',
    labelKey: 'report_reason_spam',
  );

  static const harassment = ReportCategory(
    code: 'harassment',
    labelKey: 'report_reason_harassment',
  );

  static const threat = ReportCategory(
    code: 'threat',
    labelKey: 'report_reason_threat',
  );

  static const fakeProfile = ReportCategory(
    code: 'fake_profile',
    labelKey: 'report_reason_fake_profile',
  );

  static const other = ReportCategory(
    code: 'other',
    labelKey: 'report_reason_other',
  );
}

/// Classification fields shared by every report writer.
///
/// Child-safety reports intentionally retain references only. Callers must not
/// copy message text, images, audio, or other potentially illegal media into
/// the report document.
Map<String, Object> reportClassification(ReportCategory category) => {
      'reasonCode': category.code,
      'priority': category.priority,
      if (category.isChildSafety) 'requiresChildSafetyReview': true,
    };
