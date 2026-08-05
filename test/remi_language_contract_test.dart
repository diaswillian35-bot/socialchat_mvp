import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/data/remi_lessons_data.dart';
import 'package:socialchat_mvp/services/remi_language_contract.dart';

void main() {
  group('RemiLanguageContract', () {
    test('supports exactly four stable codes', () {
      expect(
        RemiLanguageContract.supportedCodes,
        ['en', 'pt', 'es', 'fr'],
      );
    });

    test('normalizes legacy display labels to codes', () {
      expect(RemiLanguageContract.normalize('English'), 'en');
      expect(RemiLanguageContract.normalize('Português'), 'pt');
      expect(RemiLanguageContract.normalize('Español'), 'es');
      expect(RemiLanguageContract.normalize('Français'), 'fr');
      expect(RemiLanguageContract.normalize('pt-BR'), 'pt');
    });

    test('tts locale follows target language, not UI', () {
      expect(RemiLanguageContract.ttsLocale('pt'), 'pt-BR');
      expect(RemiLanguageContract.ttsLocale('en'), 'en-US');
      expect(RemiLanguageContract.ttsLocale('es'), 'es-ES');
      expect(RemiLanguageContract.ttsLocale('fr'), 'fr-FR');
    });
  });

  group('remiLessonsByCode catalog', () {
    test('every supported language has all goals and non-empty lessons', () {
      for (final code in RemiLanguageContract.supportedCodes) {
        final catalog = remiCatalogFor(code);
        expect(catalog, isNotEmpty, reason: 'catalog for $code');
        for (final goal in remiGoalIds) {
          expect(catalog.containsKey(goal), isTrue, reason: '$code/$goal');
          final lessons = catalog[goal]!;
          expect(lessons, isNotEmpty, reason: '$code/$goal lessons');
          for (final entry in lessons.entries) {
            expect(
              entry.value,
              isNotEmpty,
              reason: '$code/$goal/${entry.key} phrases',
            );
          }
        }
      }
    });
  });
}
