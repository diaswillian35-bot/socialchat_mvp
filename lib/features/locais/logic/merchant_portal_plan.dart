import '../models/place_listing.dart';

/// Fluxo futuro do comerciante. Não abre sessão, não edita e não entra no
/// roteador de deep link do app. O build Apple continua tratando `/l/{id}`
/// como página web, porque [RemdyDeepLinkParser] não conhece esta rota.
class MerchantPortalPlan {
  MerchantPortalPlan._();

  static const String contractVersion = PlaceContract.version;
  static const String origin = 'https://remdy.app';
  static const String portalPathTemplate = '/portal/locais/{id}';
  static const String deepLinkPathTemplate = '/l/{id}';

  static const List<String> stepKeys = [
    'merchant_step_portal',
    'merchant_step_contract',
    'merchant_step_read',
    'merchant_step_link',
  ];

  static Uri portalUri(String placeId) {
    _assertId(placeId);
    return Uri.parse('$origin/portal/locais/$placeId');
  }

  static Uri deepLinkUri(String placeId) {
    _assertId(placeId);
    return Uri.parse('$origin/l/$placeId');
  }

  /// Reconhece o link público futuro. Não é consultado pelo app com a flag
  /// desligada.
  static String? parsePlaceId(Uri uri) {
    if (uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    if (host != 'remdy.app' && host != 'www.remdy.app') return null;
    final segments = uri.pathSegments
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (segments.length != 2 || segments.first != 'l') return null;
    final id = segments[1];
    if (!PlaceContract.idPattern.hasMatch(id)) return null;
    return id;
  }

  static bool shouldOpenInApp(Uri uri, {required bool featureEnabled}) {
    if (!featureEnabled) return false;
    return parsePlaceId(uri) != null;
  }

  static void _assertId(String placeId) {
    if (!PlaceContract.idPattern.hasMatch(placeId)) {
      throw const PlaceContractException('id');
    }
  }
}
