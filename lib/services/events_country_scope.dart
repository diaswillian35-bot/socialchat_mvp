import 'iso_country_names.dart';

/// Identidade do 3º escopo da aba clássica Eventos (país do perfil).
///
/// Rótulo e consulta compartilham o mesmo [normalizeCountryCode] — nunca
/// misturar "Brasil" visual com query `ca`, etc.
class EventsCountryScope {
  EventsCountryScope._();

  /// Aceita apenas ISO-3166-1 alpha-2. Nomes ("Canada") → '' (sem fallback BR/CA).
  static String normalizeCountryCode(Object? raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    if (s.length != 2) return '';
    if (!RegExp(r'^[a-z]{2}$').hasMatch(s)) return '';
    return s;
  }

  static String displayName(String countryCode, String languageCode) {
    final code = normalizeCountryCode(countryCode);
    if (code.isEmpty) return '';
    return IsoCountryNames.displayName(code, languageCode);
  }

  /// Chip / título do escopo país. Sem código → chave genérica `events_country`.
  static String scopeLabel({
    required String countryCode,
    required String languageCode,
    required String Function(String key) t,
  }) {
    final name = displayName(countryCode, languageCode);
    if (name.isNotEmpty) return name;
    return t('events_country');
  }

  /// Voltar da subdivisão: estados (BR), províncias (CA), regiões (outros).
  static String subdivisionsBackLabel({
    required String countryCode,
    required String Function(String key) t,
  }) {
    switch (normalizeCountryCode(countryCode)) {
      case 'br':
        return t('events_subdivisions_back_states');
      case 'ca':
        return t('events_subdivisions_back_provinces');
      default:
        return t('events_subdivisions_back_regions');
    }
  }

  static String emptySubdivisionsLabel({
    required String countryCode,
    required String Function(String key) t,
  }) {
    switch (normalizeCountryCode(countryCode)) {
      case 'br':
        return t('events_empty_subdivisions_states');
      case 'ca':
        return t('events_empty_subdivisions_provinces');
      default:
        return t('events_empty_subdivisions_regions');
    }
  }

  static String emptySubdivisionLabel({
    required String countryCode,
    required String Function(String key) t,
  }) {
    switch (normalizeCountryCode(countryCode)) {
      case 'br':
        return t('events_empty_subdivision_state');
      case 'ca':
        return t('events_empty_subdivision_province');
      default:
        return t('events_empty_subdivision_region');
    }
  }

  static bool isBrazil(String countryCode) =>
      normalizeCountryCode(countryCode) == 'br';

  /// Query só com código normalizado; vazio = não consultar país.
  static bool canQueryCountry(String countryCode) =>
      normalizeCountryCode(countryCode).isNotEmpty;
}
