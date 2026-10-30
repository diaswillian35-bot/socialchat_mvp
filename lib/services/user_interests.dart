import 'package:cloud_firestore/cloud_firestore.dart';

import '../l10n/app_texts.dart';

/// Interesses do perfil (users/{uid}.interests, espelhado em publicUsers).
///
/// Guarda só as CHAVES (ex.: `music`), nunca o texto traduzido.
class UserInterests {
  UserInterests._();

  static const String field = 'interests';
  static const int maxCount = 20;

  /// Lista fixa (ordem de exibição; 21 opções, até 20 escolhidas). Texto em `interest_<chave>` nos 5 idiomas.
  static const List<String> keys = [
    'music',
    'football',
    'travel',
    'bars',
    'hiking',
    'beach',
    'movies',
    'games',
    'cooking',
    'parties',
    'sports',
    'art',
    'reading',
    'photography',
    'dance',
    'pets',
    'tech',
    'languages',
    'gym',
    'coffee',
    'cars',
  ];

  static String l10nKey(String key) => 'interest_$key';

  /// Texto em minúsculas (para frases: "Também curte música").
  static String label(String key, [AppTexts? t]) =>
      (t ?? AppTexts.current).get(l10nKey(key));

  /// Texto do chip (primeira letra maiúscula).
  static String chipLabel(String key, [AppTexts? t]) {
    final s = label(key, t);
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  /// Só chaves conhecidas, sem repetição, na ordem da lista fixa, até [maxCount].
  static List<String> sanitize(Iterable<Object?>? raw) {
    if (raw == null) return const [];
    final set = raw.map((e) => (e ?? '').toString().trim()).toSet();
    return keys.where(set.contains).take(maxCount).toList();
  }

  static List<String> fromUserData(Map<String, dynamic>? data) {
    final v = data?[field];
    return v is Iterable ? sanitize(v.cast<Object?>()) : const [];
  }

  /// Interesses em comum, na ordem da lista fixa.
  static List<String> common(Iterable<String> a, Iterable<String> b) {
    final sb = b.toSet();
    return sanitize(a).where(sb.contains).toList();
  }

  /// Liga/desliga [key] respeitando o limite. Retorna null se passou do limite.
  static List<String>? toggle(List<String> current, String key) {
    final next = sanitize(current);
    if (next.contains(key)) return next.where((k) => k != key).toList();
    if (next.length >= maxCount) return null;
    return sanitize([...next, key]);
  }

  /// "Também curte música" / "Também curte música e mais 2".
  static String reasonText(List<String> shared, [AppTexts? t]) {
    final tx = t ?? AppTexts.current;
    if (shared.isEmpty) return '';
    final first = label(shared.first, tx);
    if (shared.length == 1) {
      return tx
          .get('people_reason_interest_one')
          .replaceAll('{interest}', first);
    }
    return tx
        .get('people_reason_interest_more')
        .replaceAll('{interest}', first)
        .replaceAll('{count}', '${shared.length - 1}');
  }

  /// Motivo curto para o carrossel ("Curte carros").
  static String shortReasonText(List<String> shared, [AppTexts? t]) {
    final tx = t ?? AppTexts.current;
    if (shared.isEmpty) return '';
    return tx
        .get('people_reason_short_interest')
        .replaceAll('{interest}', label(shared.first, tx));
  }

  /// Grava em users e publicUsers.
  static Future<void> save(String uid, List<String> interests) async {
    final clean = sanitize(interests);
    final db = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();
    await db
        .collection('users')
        .doc(uid)
        .set({field: clean, 'updatedAt': now}, SetOptions(merge: true));
    await db
        .collection('publicUsers')
        .doc(uid)
        .set({field: clean, 'updatedAt': now}, SetOptions(merge: true));
  }
}
