import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/demo_places.dart';
import 'package:socialchat_mvp/features/locais/data/firestore_place_mapper.dart';
import 'package:socialchat_mvp/features/locais/data/place_repository.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/models/place_listing.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_detail_page.dart';

import 'locais_test_support.dart';

void main() {
  tearDown(LocaisFeatureFlag.resetDebugOverride);

  PlaceListing base() => DemoPlaces.all.first;

  Future<void> pumpPlace(WidgetTester tester, PlaceListing place) async {
    await pumpLocais(
      tester,
      LocaisDetailPage(
        placeId: place.id,
        repository: DemoPlaceRepository(catalog: [place]),
        clock: locaisDemoClock,
      ),
    );
    await tester.pumpAndSettle();
    final reviews = find.byKey(const Key('locais_detail_reviews'));
    await tester.ensureVisible(reviews);
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data ?? '';

  testWidgets('resumo usa o agregado por estrela e lista anônimo', (
    tester,
  ) async {
    final place = base().copyWith(
      rating: 4.3,
      ratingCount: 10,
      ratingCounts: {5: 6, 4: 2, 3: 1, 2: 0, 1: 1},
      reviews: const [
        PlaceReview(
          id: 'r_anon',
          authorName: 'Anônimo',
          rating: 2,
          comment: 'Demorou.',
          createdAt: '2026-10-15T18:00:00.000Z',
          anonymous: true,
        ),
        PlaceReview(
          id: 'r_ana',
          authorName: 'Ana',
          rating: 5,
          comment: 'Ótimo!',
          createdAt: '2026-10-14T12:00:00.000Z',
        ),
      ],
    );
    await pumpPlace(tester, place);

    expect(textOf(tester, 'locais_reviews_average'), '4,3');
    expect(textOf(tester, 'locais_reviews_total'), '10 avaliações');
    expect(textOf(tester, 'locais_reviews_count_5'), '6');
    expect(textOf(tester, 'locais_reviews_count_2'), '0');
    expect(textOf(tester, 'locais_reviews_count_1'), '1');
    expect(find.byKey(const Key('locais_review_r_anon')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('locais_review_r_anon')),
        matching: find.text('Anônimo'),
      ),
      findsOneWidget,
    );
    expect(find.text('Demorou.'), findsOneWidget);
    expect(find.textContaining('/10/2026'), findsWidgets);
    // Escrever avaliação continua desligado até publicar o backend.
    expect(find.byKey(const Key('place_write_review')), findsNothing);
  });

  testWidgets('sem agregado calcula pelas avaliações listadas', (
    tester,
  ) async {
    final place = base().copyWith(
      ratingCounts: const {},
      reviews: const [
        PlaceReview(
            id: 'a', authorName: 'A', rating: 5, comment: '', createdAt: ''),
        PlaceReview(
            id: 'b', authorName: 'B', rating: 3, comment: '', createdAt: ''),
      ],
    );
    await pumpPlace(tester, place);
    expect(textOf(tester, 'locais_reviews_total'), '2 avaliações');
    expect(textOf(tester, 'locais_reviews_average'), '4,0');
    expect(textOf(tester, 'locais_reviews_count_5'), '1');
    expect(textOf(tester, 'locais_reviews_count_3'), '1');
  });

  testWidgets('vazio mostra resumo zerado e "Ainda sem avaliações"', (
    tester,
  ) async {
    await pumpPlace(
        tester, base().copyWith(reviews: const [], ratingCounts: const {}));
    expect(find.byKey(const Key('locais_reviews_summary')), findsOneWidget);
    expect(find.text('Ainda sem avaliações'), findsOneWidget);
    expect(textOf(tester, 'locais_reviews_total'), '0 avaliações');
    expect(textOf(tester, 'locais_reviews_count_5'), '0');
  });

  test('mapper mascara anônimo e lê contagem por estrela', () {
    final review = FirestorePlaceMapper.tryParseReview('x', {
      'status': 'approved',
      'stars': 4,
      'anonymous': true,
      'authorDisplayName': 'Maria',
      'authorPhotoUrl': 'https://cdn.example/m.jpg',
      'createdAtIso': '2026-10-16T00:00:00.000Z',
      'editedAtIso': '2026-10-16T01:00:00.000Z',
    })!;
    expect(review.authorName, 'Anônimo');
    expect(review.authorPhotoUrl, isNull);
    expect(review.editedAt, isNotNull);

    final named = FirestorePlaceMapper.tryParseReview('y', {
      'status': 'approved',
      'stars': 5,
      'authorDisplayName': 'Maria',
      'authorPhotoUrl': 'https://cdn.example/m.jpg',
    })!;
    expect(named.authorPhotoUrl, 'https://cdn.example/m.jpg');

    expect(
      FirestorePlaceMapper.ratingCountsOf({
        'average': 4.5,
        'stars': {'5': 3, '4': 1},
      }),
      {1: 0, 2: 0, 3: 0, 4: 1, 5: 3},
    );
    expect(
      FirestorePlaceMapper.ratingCountsOf({
        'ratingCounts': {'1': 2},
      })[1],
      2,
    );
    expect(FirestorePlaceMapper.ratingCountsOf(null), isEmpty);
  });
}
