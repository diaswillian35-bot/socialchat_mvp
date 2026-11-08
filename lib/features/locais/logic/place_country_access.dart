import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../services/remdy_launch_access.dart';
import '../models/place_listing.dart';

/// Locais respeitam o país da conta, como os grupos: só aparecem locais do
/// mesmo país de casa (aberto no lançamento). Conta sem país não vê locais;
/// local sem país não aparece. Administrador vê todos.
bool canSeePlaceCountry(PlaceListing place, String? userHomeCountryCode) {
  return RemdyLaunchAccess.canAccessCountryContent(
    userHomeCountryCode: userHomeCountryCode,
    targetCountryCode: place.address.countryCode,
  );
}

List<PlaceListing> filterPlacesByCountry(
  List<PlaceListing> places,
  String? userHomeCountryCode,
) {
  return places
      .where((p) => canSeePlaceCountry(p, userHomeCountryCode))
      .toList(growable: false);
}

/// País de casa da conta atual (`homeCountryCode`, senão `countryCode`).
/// '' quando não há usuário, doc ou país.
typedef HomeCountryLoader = Future<String> Function();

Future<String> loadCurrentHomeCountryCode() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = snap.data() ?? const <String, dynamic>{};
    for (final key in const ['homeCountryCode', 'countryCode']) {
      final code = RemdyLaunchAccess.normalizeCountryCode(data[key]?.toString());
      if (code.isNotEmpty) return code;
    }
  } catch (_) {}
  return '';
}

