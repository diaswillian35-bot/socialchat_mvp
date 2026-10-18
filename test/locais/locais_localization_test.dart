import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/locais_strings.dart';

void main() {
  test('ações novas existem nos cinco idiomas sem fallback vazio', () {
    const locales = [
      Locale('pt', 'BR'),
      Locale('pt', 'PT'),
      Locale('en'),
      Locale('es'),
      Locale('fr'),
    ];
    for (final locale in locales) {
      final strings = LocaisStrings.fromLocale(locale);
      expect(strings.cancel.trim(), isNotEmpty, reason: '$locale cancel');
      expect(strings.reportPlace.trim(), isNotEmpty, reason: '$locale report');
      expect(strings.reportSent.trim(), isNotEmpty, reason: '$locale sent');
      for (final reason in const [
        'incorrect_information',
        'closed_or_missing',
        'inappropriate_photo',
        'fraud_or_impersonation',
        'other',
      ]) {
        expect(strings.reportReasonLabel(reason).trim(), isNotEmpty,
            reason: '$locale $reason');
      }
    }
  });
}
