import '../../../l10n/app_texts.dart';

/// Selo de desconto público em `places/{id}.discount` (só leitura no cliente).
class PlaceDiscount {
  const PlaceDiscount({
    required this.enabled,
    required this.percent,
    required this.validUntil,
    required this.promotionId,
    this.source = 'owner',
    this.coveredBy = 'place',
  });

  static const percents = [5, 7, 10, 15, 20];
  static const maxDays = 90;
  static const coveredByValues = ['place', 'remdy', 'shared'];
  static const conditionKey = 'show_app';

  final bool enabled;
  final int percent;
  final DateTime validUntil;
  final String promotionId;
  final String source;
  final String coveredBy;

  bool get isPartnership => source == 'partnership';

  bool isActiveAt(DateTime now) =>
      enabled && percents.contains(percent) && !validUntil.isBefore(now);

  String badgeLabel() => '−$percent%';

  static DateTime? parseTime(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toUtc();
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw)?.toUtc();
    }
    // Firestore Timestamp (evita import no modelo).
    try {
      final toDate = (raw as dynamic).toDate;
      if (toDate is Function) {
        final d = toDate() as DateTime;
        return d.toUtc();
      }
    } catch (_) {}
    if (raw is num) {
      final n = raw.toInt();
      final ms = n < 100000000000 ? n * 1000 : n;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
    return null;
  }

  static PlaceDiscount? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final percent = raw['percent'];
    final p = percent is num ? percent.toInt() : int.tryParse('$percent');
    if (p == null || !percents.contains(p)) return null;
    final until =
        parseTime(raw['validUntil']) ?? parseTime(raw['validUntilIso']);
    if (until == null) return null;
    final enabled = raw['enabled'] == true;
    final id = '${raw['promotionId'] ?? ''}';
    final source = raw['source'] == 'partnership' ? 'partnership' : 'owner';
    final covered = coveredByValues.contains(raw['coveredBy'])
        ? raw['coveredBy'] as String
        : 'place';
    return PlaceDiscount(
      enabled: enabled,
      percent: p,
      validUntil: until,
      promotionId: id,
      source: source,
      coveredBy: covered,
    );
  }

  static String formatDate(DateTime date,
      {String? languageCode, String? countryCode}) {
    final month = AppTexts.t('place_discount_month_${date.month}');
    final pattern = AppTexts.t('place_discount_date');
    return pattern
        .replaceAll('{day}', '${date.toLocal().day}')
        .replaceAll('{month}', month)
        .replaceAll('{year}', '${date.toLocal().year}');
  }

  String formatValidUntil() => formatDate(validUntil);
}
