/// Classificação pura de deep links Remdy (`https://remdy.app/...`).
///
/// Regras:
/// - `/` e URLs sem rota de app → nenhum deep link (landing no browser).
/// - Somente `/g/{code}` (e legado `/group?code=`) abrem prévia de grupo.
/// - Código ausente/inválido nunca reaproveita o último ID.
/// - `remdy://g/{code}` (esquema do Info.plist) equivale a `/g/{code}`.
/// - `intent://…#Intent;scheme=https;…` vira o `https://` correspondente.
///   No Android o sistema entrega esse intent já resolvido; o filtro
///   `scheme=https` + `pathPrefix=/g/` do manifesto é o que o recebe.

library remdy_deep_link_parser;

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

  /// `/locais/{estado}/{cidade}/{slug}`
  place,
}

class RemdyDeepLink {
  const RemdyDeepLink({
    required this.kind,
    this.groupCode,
    this.eventId,
    this.inviteRef,
    this.portalSessionId,
    this.placeSlug,
    this.clearsPendingGroup = false,
  });

  final RemdyDeepLinkKind kind;
  final String? groupCode;
  final String? eventId;
  final String? inviteRef;
  final String? portalSessionId;
  final String? placeSlug;

  /// Se true, descartar `pending_group_code` (raiz, inválido, outro destino).
  final bool clearsPendingGroup;

  bool get opensGroupPreview =>
      kind == RemdyDeepLinkKind.groupInvite && (groupCode?.isNotEmpty ?? false);
}

class RemdyDeepLinkParser {
  RemdyDeepLinkParser._();

  static const _hosts = {'remdy.app', 'www.remdy.app'};

  /// Normaliza código de convite de grupo (mesmo critério do join service).
  static String normalizeGroupCode(String? raw) {
    return (raw ?? '').trim().toUpperCase();
  }

  /// Código de grupo aceito pelo join: 3–32, `A–Z`, `0–9`, `_` e `-`.
  static bool isValidGroupCode(String? raw) {
    return _isValidGroupCode(normalizeGroupCode(raw));
  }

  /// `remdy://` e `intent://` com `scheme=https` entram no mesmo classificador
  /// que `https://remdy.app/...`.
  static Uri unwrap(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'remdy') {
      return _unwrapRemdy(uri);
    }
    if (scheme == 'intent') {
      return _unwrapIntent(uri);
    }
    return uri;
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
    return _parse(unwrap(uri));
  }

  static RemdyDeepLink _parse(Uri uri) {
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

    if (root == 'locais' && segments.length >= 4) {
      final slug = segments.last.toLowerCase();
      if (_isValidPlaceSlug(slug)) {
        return RemdyDeepLink(
          kind: RemdyDeepLinkKind.place,
          placeSlug: slug,
          clearsPendingGroup: true,
        );
      }
    }

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

  static Uri _unwrapRemdy(Uri uri) {
    final query = uri.hasQuery ? uri.query : null;
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) {
      return Uri(path: uri.path, query: query);
    }
    final path = uri.path;
    final suffix = path.isEmpty ? '' : (path.startsWith('/') ? path : '/$path');
    return Uri(path: '/$host$suffix', query: query);
  }

  /// `intent://host/path#Intent;scheme=https;package=…;end` → `https://host/path`.
  /// Outro `scheme` não é convite (o manifesto Android só declara https).
  static Uri _unwrapIntent(Uri uri) {
    final intentScheme = _intentParam(uri.fragment, 'scheme');
    if (intentScheme != 'https') {
      return Uri(scheme: 'https', host: 'invalid.invalid', path: '/');
    }
    final query = uri.hasQuery ? uri.query : null;
    final host = uri.host.trim();
    if (host.isEmpty) {
      return Uri(scheme: 'https', path: uri.path, query: query);
    }
    return Uri(
      scheme: 'https',
      host: host,
      path: uri.path.isEmpty ? '/' : uri.path,
      query: query,
    );
  }

  static String? _intentParam(String fragment, String key) {
    for (final part in fragment.split(';')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      final name = part.substring(0, idx).trim().toLowerCase();
      if (name == key) {
        return part.substring(idx + 1).trim().toLowerCase();
      }
    }
    return null;
  }

  static bool _isValidPlaceSlug(String slug) {
    return slug.length >= 3 &&
        slug.length <= 100 &&
        RegExp(r'^[a-z0-9-]+$').hasMatch(slug);
  }
}
