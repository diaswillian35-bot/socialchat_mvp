import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app escreve Locais somente pelas callables moderadas', () {
    final source = File('lib/features/locais/data/place_actions_service.dart')
        .readAsStringSync();
    expect(source, contains("httpsCallable('submitPlaceReview')"));
    expect(source, contains("httpsCallable('replyPlaceReview')"));
    expect(source, contains("httpsCallable('claimPlaceForAccount')"));
    expect(source, isNot(contains("collection('places')")));
  });

  test('avaliações públicas não expõem uid pelo Firestore', () {
    final repository = File('lib/features/locais/data/place_repository.dart')
        .readAsStringSync();
    expect(repository, contains("httpsCallable('listPlaceReviews')"));
    expect(repository, isNot(contains("collection('reviews')")));
    // As Rules ficam no repositório do portal, fora deste projeto. Ler
    // ~/Documents trava sob a proteção de privacidade do macOS, então a
    // checagem só roda quando REMDY_PORTAL_RULES aponta para o arquivo.
    final rulesPath = Platform.environment['REMDY_PORTAL_RULES'];
    if (rulesPath != null && rulesPath.isNotEmpty) {
      final rules = File(rulesPath).readAsStringSync();
      expect(rules, contains('allow list: if false'));
    }
  });

  test('backend mantém uma avaliação por uid e reivindicação idempotente', () {
    final source = File('functions/place_actions.js').readAsStringSync();
    expect(source, contains('collection("reviews").doc(uid)'));
    expect(source, contains('status: "pending"'));
    expect(source, contains('claimId(parsed.placeId, uid)'));
    expect(source, contains('type, placeId'));
  });
}
