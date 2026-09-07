/// Classificação pura de deep links Remdy (`https://remdy.app/...`).
///
/// Regras:
/// - `/` e URLs sem rota de app → nenhum deep link (landing no browser).
/// - Somente `/g/{code}` (e legado `/group?code=`) abrem prévia de grupo.
/// - Código ausente/inválido nunca reaproveita o último ID.

enum RemdyDeepLinkKind {
  /// Landing / eventos web / caminho desconhecido — sem ação no app.
  none,

  /// `/g/{code}` ou `/group?code=` com código válido → prévia (sem auto-join).
  groupInvite,

  /// `/g`, `/g/`, `/group` sem código — limpa pendência, não abre grupo.
  groupInviteInvalid,

  /// `/e|events|event/{id}`
  event,

  /// `/invite?ref=`
  invitePremium,

  /// `/portal-login/{sessionId}`
  portalLogin,
}

class RemdyDeepLink {
  const RemdyDeepLink({
    required this.kind,
    this.groupCode,
    this.eventId,
    this.inviteRef,
    this.portalSessionId,
    this.clearsPendingGroup = false,
  });

  final RemdyDeepLinkKind kind;
  final String? groupCode;
  final String? eventId;
  final String? inviteRef;
  final String? portalSessionId;

  /// Se true, descartar `pending_group_code` (raiz, inválido, outro destino).
  final bool clearsPendingGroup;

  bool get opensGroupPreview =>
      kind == RemdyDeepLinkKind.groupInvite &&
      (groupCode?.isNotEmpty ?? false);
}

class RemdyDeepLinkParser {
  RemdyDeepLinkParser._();

  static const _hosts = {'remdy.app', 'www.remdy.app'};

  /// Normaliza código de convite de grupo (mesmo critério do join service).
  static String normalizeGroupCode(String? raw) {
    return (raw ?? '').trim().toUpperCase();
  }

  static bool isAllowedHost(Uri uri) {
    final host = uri.host.toLowerCase().trim();
    if (host.isEmpty) {
      // Custom schemes / relative — permitir path-only em testes.
      return uri.scheme.isEmpty ||
          uri.scheme == 'https' ||
          uri.scheme == 'http';
    }
    return _hosts.contains(host);
  }

  static RemdyDeepLink parse(Uri uri) {
    if (!isAllowedHost(uri)) {
      return const RemdyDeepLink(
        kind: RemdyDeepLinkKind.none,
        clearsPendingGroup: true,
      );
    }

    final segments = uri.pathSegments
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // https://remdy.app  /  https://remdy.app/
    if (segments.isEmpty) {
      return const RemdyDeepLink(
        kind: RemdyDeepLinkKind.none,
        clearsPendingGroup: true,
      );
    }

    final root = segments.first.toLowerCase();

    // /g/{code}
    if (root == 'g') {
      if (segments.length < 2) {
        return const RemdyDeepLink(
          kind: RemdyDeepLinkKind.groupInviteInvalid,
          clearsPendingGroup: true,
        );
      }
      final code = normalizeGroupCode(segments[1]);
      if (code.isEmpty || !_isValidGroupCode(code)) {
        return const RemdyDeepLink(
          kind: RemdyDeepLinkKind.groupInviteInvalid,
          clearsPendingGroup: true,
        );
      }
      return RemdyDeepLink(
        kind: RemdyDeepLinkKind.groupInvite,
        groupCode: code,
        clearsPendingGroup: false,
      );
    }

    // /group?code=
    if (root == 'group') {
      final code = normalizeGroupCode(uri.queryParameters['code']);
      if (code.isEmpty || !_isValidGroupCode(code)) {
        return const RemdyDeepLink(
          kind: RemdyDeepLinkKind.groupInviteInvalid,
          clearsPendingGroup: true,
        );
      }
      return RemdyDeepLink(
        kind: RemdyDeepLinkKind.groupInvite,
        groupCode: code,
        clearsPendingGroup: false,
      );
    }

    // /e|events|event/{id}
    if (root == 'e' || root == 'events' || root == 'event') {
      if (segments.length < 2) {
        return const RemdyDeepLink(
          kind: RemdyDeepLinkKind.none,
          clearsPendingGroup: true,
        );
      }
      final eventId = segments[1].trim();
      if (eventId.isEmpty ||
          eventId.length > 128 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(eventId)) {
        return const RemdyDeepLink(
          kind: RemdyDeepLinkKind.none,
          clearsPendingGroup: true,
        );
      }
      return RemdyDeepLink(
        kind: RemdyDeepLinkKind.event,
        eventId: eventId,
        clearsPendingGroup: true,
      );
    }

    // /portal-login/{sessionId}
    if (root == 'portal-login') {
      if (segments.length < 2) {
        return const RemdyDeepLink(
          kind: RemdyDeepLinkKind.none,
          clearsPendingGroup: true,
        );
      }
      final sessionId = segments[1].trim();
      if (sessionId.isEmpty) {
        return const RemdyDeepLink(
          kind: RemdyDeepLinkKind.none,
          clearsPendingGroup: true,
        );
      }
      return RemdyDeepLink(
        kind: RemdyDeepLinkKind.portalLogin,
        portalSessionId: sessionId,
        clearsPendingGroup: true,
      );
    }

    // /invite?ref=  (+ legado ?code= grupo)
    if (root == 'invite') {
      final groupCode = normalizeGroupCode(uri.queryParameters['code']);
      if (groupCode.isNotEmpty && _isValidGroupCode(groupCode)) {
        return RemdyDeepLink(
          kind: RemdyDeepLinkKind.groupInvite,
          groupCode: groupCode,
          inviteRef: (uri.queryParameters['ref'] ?? '').trim().isEmpty
              ? null
              : (uri.queryParameters['ref'] ?? '').trim(),
          clearsPendingGroup: false,
        );
      }
      final ref = (uri.queryParameters['ref'] ?? '').trim();
      if (ref.isEmpty) {
        return const RemdyDeepLink(
          kind: RemdyDeepLinkKind.none,
          clearsPendingGroup: true,
        );
      }
      return RemdyDeepLink(
        kind: RemdyDeepLinkKind.invitePremium,
        inviteRef: ref,
        clearsPendingGroup: true,
      );
    }

    // /eventos e demais páginas web → sem deep link de grupo
    return const RemdyDeepLink(
      kind: RemdyDeepLinkKind.none,
      clearsPendingGroup: true,
    );
  }

  static bool _isValidGroupCode(String code) {
    // Códigos Remdy: alfanumérico curto; rejeita path lixo.
    if (code.length < 3 || code.length > 32) return false;
    return RegExp(r'^[A-Z0-9_-]+$').hasMatch(code);
  }
}
