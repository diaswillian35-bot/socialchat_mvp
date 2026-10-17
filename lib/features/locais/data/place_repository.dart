import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../locais_feature_flag.dart';
import '../models/place_listing.dart';
import 'demo_places.dart';
import 'firestore_place_mapper.dart';

/// Leitura do contrato `places.v1`. Esta etapa não escreve e não conhece
/// credencial de produção nem serviço remoto.
abstract class PlaceRepository {
  Future<List<PlaceListing>> fetchCatalog();

  Future<PlaceListing?> fetchById(String id);

  Future<bool> canManage(String id) async => false;
}

class PlaceAccessBlocked implements Exception {
  const PlaceAccessBlocked();

  @override
  String toString() => 'PlaceAccessBlocked';
}

/// Flag desligada: recusa a leitura sem rede e sem serviço remoto.
class BlockedPlaceRepository implements PlaceRepository {
  const BlockedPlaceRepository();

  @override
  Future<List<PlaceListing>> fetchCatalog() async {
    throw const PlaceAccessBlocked();
  }

  @override
  Future<PlaceListing?> fetchById(String id) async {
    throw const PlaceAccessBlocked();
  }

  @override
  Future<bool> canManage(String id) async => false;
}

class DemoPlaceRepository implements PlaceRepository {
  DemoPlaceRepository({
    this.latency = Duration.zero,
    this.failure,
    List<PlaceListing>? catalog,
  }) : _catalog = List<PlaceListing>.unmodifiable(catalog ?? DemoPlaces.all);

  final Duration latency;
  final Object? failure;
  final List<PlaceListing> _catalog;

  @override
  Future<List<PlaceListing>> fetchCatalog() async {
    await _guard();
    return _catalog;
  }

  @override
  Future<PlaceListing?> fetchById(String id) async {
    await _guard();
    for (final place in _catalog) {
      if (place.id == id) return place;
    }
    return null;
  }

  @override
  Future<bool> canManage(String id) async => false;

  Future<void> _guard() async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    if (failure != null) throw failure!;
  }
}

/// Catálogo de produção. Lê exclusivamente a coleção `places` usada pelo
/// portal e pelo Admin. Locais não publicados, inativos ou apagados nunca são
/// devolvidos, mesmo se uma Rules mal configurada permitisse a leitura.
class FirestorePlaceRepository implements PlaceRepository {
  FirestorePlaceRepository(
      {FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _firestoreOverride = firestore,
        _functionsOverride = functions;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseFunctions? _functionsOverride;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  Query<Map<String, dynamic>> get _publicQuery => _firestore
      .collection('places')
      .where('schemaVersion', isEqualTo: 1)
      .where('moderationStatus', isEqualTo: 'published')
      .where('active', isEqualTo: true)
      .where('deleted', isEqualTo: false)
      .limit(80);

  @override
  Future<List<PlaceListing>> fetchCatalog() async {
    final snapshot = await _publicQuery.get();
    final places = <PlaceListing>[];
    for (final document in snapshot.docs) {
      final place = FirestorePlaceMapper.tryParse(document.id, document.data());
      if (place != null) places.add(place);
    }
    places.sort((a, b) {
      final rating = b.rating.compareTo(a.rating);
      return rating != 0 ? rating : a.name.compareTo(b.name);
    });
    return places;
  }

  @override
  Future<PlaceListing?> fetchById(String id) async {
    final document = await _firestore.collection('places').doc(id).get();
    final data = document.data();
    if (!document.exists || data == null) return null;
    final place = FirestorePlaceMapper.tryParse(id, data);
    if (place == null) return null;
    // Avaliações são opcionais: se a função não existir ou falhar, a ficha
    // abre mesmo assim, sem avaliações.
    final Map<String, dynamic> payload;
    try {
      final callable = (_functionsOverride ??
              FirebaseFunctions.instanceFor(region: 'us-central1'))
          .httpsCallable('listPlaceReviews');
      final response = await callable.call({'placeId': id});
      payload = Map<String, dynamic>.from(response.data as Map);
    } catch (_) {
      return place;
    }
    final rawReviews =
        payload['reviews'] is List ? payload['reviews'] as List : const [];
    final reviews = <PlaceReview>[];
    for (var index = 0; index < rawReviews.length; index++) {
      final raw = rawReviews[index];
      if (raw is! Map) continue;
      final review = FirestorePlaceMapper.tryParseReview(
        'public_$index',
        Map<String, dynamic>.from(raw),
      );
      if (review != null) reviews.add(review);
    }
    final summary = payload['summary'];
    if (summary is Map) {
      final counts = FirestorePlaceMapper.ratingCountsOf(summary);
      final count = summary['count'];
      final average = summary['average'];
      return place.copyWith(
        reviews: reviews,
        ratingCounts: counts.isEmpty ? null : counts,
        ratingCount: count is num && count > 0 ? count.toInt() : null,
        rating: average is num && average > 0
            ? average.toDouble().clamp(0, 5).toDouble()
            : null,
      );
    }
    return place.copyWith(reviews: reviews);
  }

  @override
  Future<bool> canManage(String id) async {
    try {
      final doc = await _firestore
          .collection('places')
          .doc(id)
          .collection('private')
          .doc('access')
          .get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }
}

PlaceRepository createPlaceRepository({PlaceRepository? override}) {
  if (override != null) return override;
  if (!LocaisFeatureFlag.isEnabled) return const BlockedPlaceRepository();
  return FirestorePlaceRepository();
}
