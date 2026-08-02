/// Catálogo dos estados brasileiros (nome + UF) e normalização.
class BrazilStates {
  BrazilStates._();

  static const List<BrazilStateInfo> all = [
    BrazilStateInfo(name: 'Acre', uf: 'AC'),
    BrazilStateInfo(name: 'Alagoas', uf: 'AL'),
    BrazilStateInfo(name: 'Amapá', uf: 'AP'),
    BrazilStateInfo(name: 'Amazonas', uf: 'AM'),
    BrazilStateInfo(name: 'Bahia', uf: 'BA'),
    BrazilStateInfo(name: 'Ceará', uf: 'CE'),
    BrazilStateInfo(name: 'Distrito Federal', uf: 'DF'),
    BrazilStateInfo(name: 'Espírito Santo', uf: 'ES'),
    BrazilStateInfo(name: 'Goiás', uf: 'GO'),
    BrazilStateInfo(name: 'Maranhão', uf: 'MA'),
    BrazilStateInfo(name: 'Mato Grosso', uf: 'MT'),
    BrazilStateInfo(name: 'Mato Grosso do Sul', uf: 'MS'),
    BrazilStateInfo(name: 'Minas Gerais', uf: 'MG'),
    BrazilStateInfo(name: 'Pará', uf: 'PA'),
    BrazilStateInfo(name: 'Paraíba', uf: 'PB'),
    BrazilStateInfo(name: 'Paraná', uf: 'PR'),
    BrazilStateInfo(name: 'Pernambuco', uf: 'PE'),
    BrazilStateInfo(name: 'Piauí', uf: 'PI'),
    BrazilStateInfo(name: 'Rio de Janeiro', uf: 'RJ'),
    BrazilStateInfo(name: 'Rio Grande do Norte', uf: 'RN'),
    BrazilStateInfo(name: 'Rio Grande do Sul', uf: 'RS'),
    BrazilStateInfo(name: 'Rondônia', uf: 'RO'),
    BrazilStateInfo(name: 'Roraima', uf: 'RR'),
    BrazilStateInfo(name: 'Santa Catarina', uf: 'SC'),
    BrazilStateInfo(name: 'São Paulo', uf: 'SP'),
    BrazilStateInfo(name: 'Sergipe', uf: 'SE'),
    BrazilStateInfo(name: 'Tocantins', uf: 'TO'),
  ];

  static final Map<String, BrazilStateInfo> _byNorm = () {
    final map = <String, BrazilStateInfo>{};
    for (final s in all) {
      map[_normalize(s.name)] = s;
      map[_normalize(s.uf)] = s;
    }
    // Aliases comuns
    map[_normalize('DF')] = all.firstWhere((e) => e.uf == 'DF');
    map[_normalize('Brasilia')] = all.firstWhere((e) => e.uf == 'DF');
    map[_normalize('Brasília')] = all.firstWhere((e) => e.uf == 'DF');
    return map;
  }();

  static String _normalize(String raw) {
    final lower = raw.trim().toLowerCase();
    return lower
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c');
  }

  /// Resolve nome ou UF para um estado canônico. Retorna null se inválido.
  static BrazilStateInfo? resolve(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return _byNorm[_normalize(trimmed)];
  }

  /// Chave estável para agrupamento (UF quando conhecido, senão nome normalizado).
  static String groupingKey(String? raw) {
    final info = resolve(raw);
    if (info != null) return info.uf;
    final trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty) return '';
    return _normalize(trimmed);
  }

  static String displayName(String? raw) {
    final info = resolve(raw);
    if (info != null) return info.name;
    final trimmed = (raw ?? '').trim();
    return trimmed;
  }

  static String displayUf(String? raw) {
    final info = resolve(raw);
    if (info != null) return info.uf;
    final trimmed = (raw ?? '').trim();
    if (trimmed.length == 2) return trimmed.toUpperCase();
    return '';
  }
}

class BrazilStateInfo {
  const BrazilStateInfo({required this.name, required this.uf});

  final String name;
  final String uf;
}
