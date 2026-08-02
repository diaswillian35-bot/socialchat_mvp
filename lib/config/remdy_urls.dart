/// URLs canônicas Remdy (app + portais web).
abstract class RemdyUrls {
  static const String appOrigin = 'https://remdy.app';

  /// Portal de organização de eventos (novos acessos).
  static const String eventsPortal = 'https://remdy-events.web.app';

  /// Hosting antigo do portal — permanece ativo para QR Codes já emitidos.
  static const String eventsPortalLegacy = 'https://remdy-events-web.web.app';

  /// Deep link do app para aprovar login QR no portal.
  static const String portalQrLoginBase = '$appOrigin/portal-login';

  static Uri eventsPortalUri([String path = '/']) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$eventsPortal$normalized');
  }

  static Uri organizeEventsUri() => eventsPortalUri('/organizer');

  static Uri createEventUri() => eventsPortalUri('/create-event');
}
