import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Criação e edição segura de eventos via Cloud Functions.
class EventManagementService {
  EventManagementService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static String _newRequestId() {
    final ms = DateTime.now().microsecondsSinceEpoch;
    final r = Random().nextInt(1 << 32);
    return 'e_${ms}_$r';
  }

  static Future<Map<String, dynamic>> createEvent({
    required String title,
    required String description,
    required String category,
    required DateTime startAt,
    required String city,
    required String cityKey,
    required String stateName,
    required String placeName,
    required String address,
    required String placeDisplay,
    required String countryCode,
    required String regionKey,
    required String scope,
    double? lat,
    double? lng,
    required bool sponsorInterested,
    String? coverUrl,
    List<String>? photoUrls,
  }) async {
    final payload = <String, dynamic>{
      'requestId': _newRequestId(),
      'title': title,
      'description': description,
      'category': category,
      'startAtMs': startAt.millisecondsSinceEpoch,
      'city': city,
      'cityKey': cityKey,
      'stateName': stateName,
      'placeName': placeName,
      'address': address,
      'placeDisplay': placeDisplay,
      'countryCode': countryCode,
      'regionKey': regionKey,
      'scope': scope,
      'lat': lat,
      'lng': lng,
      'sponsorInterested': sponsorInterested,
    };
    if (coverUrl != null && coverUrl.trim().isNotEmpty) {
      payload['coverUrl'] = coverUrl.trim();
    }
    if (photoUrls != null && photoUrls.isNotEmpty) {
      payload['photoUrls'] = photoUrls;
    }

    final callable = _functions.httpsCallable('createEvent');
    final result = await callable.call(payload);
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<Map<String, dynamic>> updateEvent({
    required String eventId,
    String? title,
    String? description,
    String? category,
    DateTime? startAt,
    String? city,
    String? cityKey,
    String? stateName,
    String? placeName,
    String? address,
    String? placeDisplay,
    String? countryCode,
    String? regionKey,
    String? scope,
    double? lat,
    double? lng,
    bool? clearLatLng,
    bool? sponsorInterested,
    String? coverUrl,
    List<String>? photoUrls,
  }) async {
    final payload = <String, dynamic>{
      'eventId': eventId,
    };
    if (title != null) payload['title'] = title;
    if (description != null) payload['description'] = description;
    if (category != null) payload['category'] = category;
    if (startAt != null) {
      payload['startAtMs'] = startAt.millisecondsSinceEpoch;
    }
    if (city != null) payload['city'] = city;
    if (cityKey != null) payload['cityKey'] = cityKey;
    if (stateName != null) payload['stateName'] = stateName;
    if (placeName != null) payload['placeName'] = placeName;
    if (address != null) payload['address'] = address;
    if (placeDisplay != null) payload['placeDisplay'] = placeDisplay;
    if (countryCode != null) payload['countryCode'] = countryCode;
    if (regionKey != null) payload['regionKey'] = regionKey;
    if (scope != null) payload['scope'] = scope;
    if (clearLatLng == true) {
      payload['lat'] = null;
      payload['lng'] = null;
    } else {
      if (lat != null) payload['lat'] = lat;
      if (lng != null) payload['lng'] = lng;
    }
    if (sponsorInterested != null) {
      payload['sponsorInterested'] = sponsorInterested;
    }
    if (coverUrl != null) payload['coverUrl'] = coverUrl;
    if (photoUrls != null) payload['photoUrls'] = photoUrls;

    final callable = _functions.httpsCallable('updateEvent');
    final result = await callable.call(payload);
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Remove evento pending incompleto (ex.: falha no upload das fotos).
  static Future<void> abortIncompleteEvent({
    required String eventId,
    String reason = 'upload_or_finalize_failed',
  }) async {
    try {
      debugPrint('[CREATE EVENT] abortIncompleteEvent: $eventId ($reason)');
      final callable = _functions.httpsCallable('abortIncompleteEvent');
      await callable.call(<String, dynamic>{
        'eventId': eventId,
        'reason': reason,
      });
    } catch (e) {
      debugPrint('[CREATE EVENT] abortIncompleteEvent failed: $e');
    }
  }


  static Future<void> cancelEvent({required String eventId}) async {
    final callable = _functions.httpsCallable('cancelEvent');
    await callable.call(<String, dynamic>{'eventId': eventId});
  }

  static String cancelErrorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'event_management_no_permission';
      case 'not-found':
      case 'failed-precondition':
        return 'event_management_unavailable';
      default:
        return 'event_management_update_error';
    }
  }

  static String createErrorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'event_detail_login_required';
      case 'invalid-argument':
        return 'event_management_invalid_data';
      case 'permission-denied':
        return 'event_management_create_error';
      case 'failed-precondition':
        return 'event_management_unavailable';
      default:
        return 'event_management_create_error';
    }
  }

  static String updateErrorKey(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'event_management_no_permission';
      case 'not-found':
      case 'failed-precondition':
        return 'event_management_unavailable';
      case 'invalid-argument':
        return 'event_management_invalid_data';
      default:
        return 'event_management_update_error';
    }
  }
}
