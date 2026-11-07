import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/models/event_editorial_draft.dart';

void main() {
  test('seletor não oferece Restaurante nem café', () {
    final items = eventCategoryPickerItems('Geral');
    expect(items, isNot(contains('Restaurante')));
    expect(items, isNot(contains('café')));
    expect(items, containsAll(['Show', 'Geral', 'Cultura']));
  });
  test('evento antigo com categoria legada mantém o valor no seletor', () {
    expect(eventCategoryPickerItems('Restaurante'), contains('Restaurante'));
    expect(eventCategoryPickerItems('café'), contains('café'));
    expect(eventCategoryPickerItems('café').where((c) => c == 'café').length, 1);
  });
  test('categorias legadas continuam válidas (compat. com CF)', () {
    expect(kEventEditorialCategories, containsAll(['Restaurante', 'café']));
    const d = EventEditorialDraft(category: 'Restaurante');
    expect(d.copyWith(title: 'x').category, 'Restaurante');
  });
}
