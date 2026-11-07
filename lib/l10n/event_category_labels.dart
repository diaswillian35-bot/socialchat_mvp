import 'app_texts.dart';

/// Chave l10n de cada valor de categoria de evento gravado no Firestore.
/// Só exibição: o valor gravado nunca muda.
const Map<String, String> kEventCategoryLabelKeys = {
  'Show': 'events_cat_show',
  'Geral': 'events_general',
  'Esportes': 'events_sports',
  'Música': 'events_music',
  'Cultura': 'events_culture',
  'Idiomas': 'events_languages',
  'Festival': 'events_cat_festival',
  'Cultural': 'events_cat_cultural',
  'Restaurante': 'events_restaurant',
  'café': 'events_cat_cafe',
};

String? eventCategoryLabelKey(String raw) {
  final v = raw.trim();
  final exact = kEventCategoryLabelKeys[v];
  if (exact != null) return exact;
  final lower = v.toLowerCase();
  for (final e in kEventCategoryLabelKeys.entries) {
    if (e.key.toLowerCase() == lower) return e.value;
  }
  return null;
}

/// Rótulo traduzido; valores desconhecidos/legados mostram o valor cru.
String eventCategoryLabel(String raw) {
  final key = eventCategoryLabelKey(raw);
  if (key == null) return raw;
  final label = AppTexts.t(key);
  return label == key ? raw : label;
}
