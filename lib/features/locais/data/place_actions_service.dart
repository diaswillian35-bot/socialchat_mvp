import 'package:cloud_functions/cloud_functions.dart';

import '../locais_feature_flag.dart';

class PlaceActionException implements Exception {
  const PlaceActionException(this.code);
  final String code;
}

class PlaceActionsService {
  const PlaceActionsService({FirebaseFunctions? functions})
      : _override = functions;

  final FirebaseFunctions? _override;
  FirebaseFunctions get _functions =>
      _override ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  void _guard() {
    if (!LocaisFeatureFlag.isEnabled) {
      throw const PlaceActionException('feature-disabled');
    }
  }

  Future<String> submitReview({
    required String placeId,
    required int stars,
    required String comment,
  }) async {
    _guard();
    final result = await _functions.httpsCallable('submitPlaceReview').call({
      'placeId': placeId,
      'stars': stars,
      'comment': comment.trim(),
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['action']?.toString() ?? 'updated';
  }

  Future<void> reply({
    required String placeId,
    required String reviewId,
    required String text,
  }) async {
    _guard();
    await _functions.httpsCallable('replyPlaceReview').call({
      'placeId': placeId,
      'reviewId': reviewId,
      'text': text.trim(),
    });
  }

  Future<String> claim({
    required String placeId,
    required String role,
    required String phone,
    required String note,
  }) async {
    _guard();
    final result = await _functions.httpsCallable('claimPlaceForAccount').call({
      'placeId': placeId,
      'role': role,
      'phone': phone.trim(),
      'note': note.trim(),
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['protocol']?.toString() ?? '';
  }
}
