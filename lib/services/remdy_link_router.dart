/// Callback global para deep links oficiais Remdy (sem aviso externo).
class RemdyLinkRouter {
  RemdyLinkRouter._();

  static Future<void> Function(Uri uri)? handler;

  static Future<bool> open(Uri uri) async {
    final h = handler;
    if (h == null) return false;
    await h(uri);
    return true;
  }
}
