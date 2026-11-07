/// One canonical, case-preserving public link for app shares and tests.
class PlaceShareLink {
  PlaceShareLink._();

  static String url(String placeId) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(placeId)) {
      throw ArgumentError.value(placeId, 'placeId');
    }
    return 'https://remdy.app/l/$placeId';
  }
}
