import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/l10n/event_category_labels.dart';
import 'package:socialchat_mvp/models/event_editorial_draft.dart';

Map<String, dynamic> _load(String c) =>
    jsonDecode(File('lib/l10n/$c.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  const locales = ['pt-BR', 'pt-PT', 'en', 'es', 'fr'];

  test('toda categoria tem chave e texto nas 5 línguas', () {
    for (final c in kEventEditorialCategories) {
      final key = eventCategoryLabelKey(c);
      expect(key, isNotNull, reason: c);
      for (final l in locales) {
        final v = _load(l)[key];
        expect(v is String && v.trim().isNotEmpty, isTrue, reason: '$l $key');
      }
    }
  });

  test('Cultura e Cultural ficam distintos em cada língua', () {
    for (final l in locales) {
      final m = _load(l);
      expect(m['events_culture'], isNot(m['events_cat_cultural']), reason: l);
    }
  });

  test('rótulo traduzido; desconhecido mostra valor cru', () {
    AppTexts.loadFromMap(_load('en'));
    expect(eventCategoryLabel('Esportes'), 'Sports');
    expect(eventCategoryLabel('café'), 'Café');
    expect(eventCategoryLabel('Restaurante'), 'Restaurant');
    expect(eventCategoryLabel('Cultural'), 'Cultural');
    expect(eventCategoryLabel('Cultura'), 'Culture');
    expect(eventCategoryLabel('Xyz'), 'Xyz');
    AppTexts.loadFromMap(_load('fr'));
    expect(eventCategoryLabel('Show'), 'Spectacle');
  });

  test('valor gravado não muda ao escolher', () {
    const d = EventEditorialDraft();
    for (final c in kEventSelectableCategories) {
      expect(d.copyWith(category: c).category, c);
      expect(d.copyWith(category: c).toJson()['category'], c);
    }
  });
}
