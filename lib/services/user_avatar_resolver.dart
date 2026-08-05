/// Resolve a foto pública de um usuário a partir de documentos heterogêneos.
///
/// Contas antigas gravam `users.photoUrl`; contas novas criadas pelo login
/// gravam `users.profilePhotoUrl` e `publicUsers.photoUrl`. Sem uma cadeia
/// única de fallback os cards ficam sem foto conforme a origem da conta.
class UserAvatarResolver {
  UserAvatarResolver._();

  /// Ordem canônica de campos de avatar aceitos em `users` / `publicUsers`.
  static const List<String> fieldPriority = <String>[
    'photoUrl',
    'profilePhotoUrl',
    'photoURL',
    'avatarUrl',
    'imageUrl',
  ];

  /// Retorna a primeira URL de avatar válida ou `''` quando não houver.
  static String resolve(Map<String, dynamic>? data) {
    if (data == null) return '';
    for (final field in fieldPriority) {
      final candidate = sanitize(data[field]);
      if (candidate.isNotEmpty) return candidate;
    }
    return '';
  }

  /// Normaliza um valor cru: aceita apenas HTTPS absoluto e bem formado.
  static String sanitize(Object? raw) {
    if (raw == null) return '';
    final value = raw.toString().trim();
    if (value.isEmpty) return '';
    if (value == 'null' || value == 'undefined') return '';

    final uri = Uri.tryParse(value);
    if (uri == null) return '';
    if (!uri.isAbsolute) return '';
    if (uri.scheme.toLowerCase() != 'https') return '';
    if (uri.host.trim().isEmpty) return '';

    return value;
  }

  /// Inicial neutra para o avatar de fallback.
  static String initialFor(String? name) {
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}
