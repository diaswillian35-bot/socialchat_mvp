import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import '../locais_feature_flag.dart';

typedef PlaceTranslationCall = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> data);

/// Server owns persistent hash cache and spending limits. Client coalesces requests.
class PlaceDescriptionTranslationService {
  PlaceDescriptionTranslationService({PlaceTranslationCall? call})
      : _call = call;
  static final shared = PlaceDescriptionTranslationService();
  final PlaceTranslationCall? _call;
  final _session = <String, Future<String?>>{};

  static String target(Locale locale) =>
      const ['pt', 'en', 'es', 'fr'].contains(locale.languageCode)
          ? locale.languageCode
          : 'en';
  static String sourceHash(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  Future<String?> load(String placeId, String original, Locale locale) {
    if (!LocaisFeatureFlag.isEnabled ||
        original.isEmpty ||
        original.runes.length > 5000) {
      return Future.value(null);
    }
    final lang = target(locale);
    final digest = sourceHash(original);
    final key = '$placeId/$lang/$digest';
    final previous = _session[key];
    if (previous != null) return previous;
    if (_session.length >= 128) _session.remove(_session.keys.first);
    return _session[key] = _fetch(placeId, lang, digest);
  }

  Future<String?> _fetch(String id, String lang, String digest) async {
    try {
      final data = {'placeId': id, 'language': lang, 'sourceHash': digest};
      final Map<String, dynamic> result;
      final call = _call;
      if (call != null) {
        result = await call(data);
      } else {
        final response =
            await FirebaseFunctions.instanceFor(region: 'us-central1')
                .httpsCallable('translatePlaceDescription')
                .call(data);
        result = Map<String, dynamic>.from(response.data as Map);
      }
      final text = result['text'];
      if (result['translated'] != true ||
          result['sourceHash'] != digest ||
          result['targetLanguage'] != lang ||
          text is! String ||
          text.isEmpty ||
          text.length > 20000) {
        return null;
      }
      return text;
    } catch (_) {
      // Offline, disabled API, missing function, denied age/auth or cap: original.
      return null;
    }
  }
}
