import 'package:cloud_firestore/cloud_firestore.dart';

/// Remote (Firestore) config for people browse — no app release needed to change.
///
/// Document: `appConfig/peopleBrowse`
/// Field: `citySectionMinProfiles` (int, default 30)
class PeopleBrowseConfigService {
  PeopleBrowseConfigService._();

  static const String collection = 'appConfig';
  static const String docId = 'peopleBrowse';
  static const String fieldCitySectionMin = 'citySectionMinProfiles';
  static const int defaultCitySectionMin = 30;

  static int _cachedMin = defaultCitySectionMin;
  static DateTime? _cachedAt;
  static const Duration _ttl = Duration(minutes: 5);

  static int get cachedCitySectionMinProfiles => _cachedMin;

  static Future<int> citySectionMinProfiles({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _ttl) {
      return _cachedMin;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection(collection)
          .doc(docId)
          .get();
      final raw = snap.data()?[fieldCitySectionMin];
      final n = raw is int
          ? raw
          : (raw is num ? raw.toInt() : defaultCitySectionMin);
      _cachedMin = n.clamp(1, 500);
      _cachedAt = now;
    } catch (_) {
      // Keep last cache / default — offline safe.
    }
    return _cachedMin;
  }
}
