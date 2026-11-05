import 'package:timezone/timezone.dart' as tz;

import '../models/place_listing.dart';

/// Um grupo do editor: vários dias com o mesmo horário.
class PlaceHoursGroup {
  PlaceHoursGroup({Set<int>? days, this.opens = '09:00', this.closes = '18:00'})
      : days = days ?? <int>{};

  final Set<int> days;
  String opens;
  String closes;
}

/// Horário estruturado (`hours` no Firestore), fuso do local e leitura
/// tolerante do texto antigo (`hoursNote`).
class PlaceHoursLogic {
  PlaceHoursLogic._();

  static final RegExp _clock = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  static bool isClock(String v) => _clock.hasMatch(v);

  // ---------- Firestore: { v: 1, days: { "1": [{o, c}], ... } } ----------

  static Map<String, dynamic> toJson(List<PlaceHours> slots) {
    final days = <String, dynamic>{};
    for (var d = 1; d <= 7; d++) {
      days['$d'] = [
        for (final s in slots.where((s) => s.weekday == d))
          {'o': s.opens, 'c': s.closes},
      ];
    }
    return {'v': 1, 'days': days};
  }

  /// Nulo quando não há campo estruturado válido.
  static List<PlaceHours>? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final days = raw['days'];
    if (days is! Map) return null;
    final result = <PlaceHours>[];
    for (var d = 1; d <= 7; d++) {
      final list = days['$d'];
      if (list is! List) continue;
      for (final item in list.take(2)) {
        if (item is! Map) continue;
        final o = (item['o'] ?? '').toString();
        final c = (item['c'] ?? '').toString();
        if (!isClock(o) || !isClock(c) || o == c) continue;
        result.add(PlaceHours(weekday: d, opens: o, closes: c));
      }
    }
    // Vazio = sem horário estruturado: vale o texto antigo, se houver.
    return result.isEmpty ? null : result;
  }

  // ---------- grupos do editor <-> dias ----------

  static List<PlaceHoursGroup> toGroups(List<PlaceHours> slots) {
    final groups = <PlaceHoursGroup>[];
    for (var d = 1; d <= 7; d++) {
      final mine = slots.where((s) => s.weekday == d).toList();
      if (mine.isEmpty) continue;
      // Editor tem uma faixa por grupo; a 1ª faixa do dia vale.
      final s = mine.first;
      final g = groups.where((g) => g.opens == s.opens && g.closes == s.closes);
      if (g.isNotEmpty) {
        g.first.days.add(d);
      } else {
        groups
            .add(PlaceHoursGroup(days: {d}, opens: s.opens, closes: s.closes));
      }
    }
    return groups;
  }

  /// Um dia em dois grupos: vale o primeiro. Dias fora de grupo = fechado.
  static List<PlaceHours> fromGroups(List<PlaceHoursGroup> groups) {
    final used = <int>{};
    final result = <PlaceHours>[];
    for (final g in groups) {
      if (!isClock(g.opens) || !isClock(g.closes) || g.opens == g.closes) {
        continue;
      }
      for (final d in (g.days.toList()..sort())) {
        if (d < 1 || d > 7 || !used.add(d)) continue;
        result.add(PlaceHours(weekday: d, opens: g.opens, closes: g.closes));
      }
    }
    result.sort((a, b) => a.weekday.compareTo(b.weekday));
    return result;
  }

  /// Texto gravado em `hoursNote` (o backend atual só guarda esse campo).
  /// Todos os dias iguais: `HH:MM-HH:MM` (legível pelo build atual).
  static String toNote(List<PlaceHours> slots, String Function(int) dayName) {
    if (slots.isEmpty) return '';
    final first = slots.first;
    final allSame = slots.length == 7 &&
        List.generate(7, (i) => i + 1).every((d) => slots.any((s) =>
            s.weekday == d &&
            s.opens == first.opens &&
            s.closes == first.closes));
    if (allSame) return '${first.opens}-${first.closes}';
    final lines = <String>[];
    for (var d = 1; d <= 7; d++) {
      final mine = slots.where((s) => s.weekday == d);
      if (mine.isEmpty) continue;
      lines.add(
          '${dayName(d)}: ${mine.map((s) => '${s.opens}-${s.closes}').join(', ')}');
    }
    return lines.join('\n');
  }

  // ---------- leitura do texto antigo (5 idiomas) ----------

  static const Map<String, int> _dayPrefix = {
    'seg': 1,
    'ter': 2,
    'qua': 3,
    'qui': 4,
    'sex': 5,
    'sab': 6,
    'dom': 7,
    'mon': 1,
    'tue': 2,
    'wed': 3,
    'thu': 4,
    'fri': 5,
    'sat': 6,
    'sun': 7,
    'lun': 1,
    'mar': 2,
    'mie': 3,
    'jue': 4,
    'vie': 5,
    'mer': 3,
    'jeu': 4,
    'ven': 5,
    'sam': 6,
    'dim': 7,
  };

  static const List<String> _allDaysWords = [
    'todos',
    'todas',
    'every',
    'daily',
    'diari',
    'tous',
    'toda',
  ];
  static const List<String> _closedWords = [
    'fechad',
    'closed',
    'cerrad',
    'ferme',
  ];

  static String _fold(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  static final RegExp _range = RegExp(
    r'(\d{1,2})(?:[:h.](\d{2})|h)?\s*(?:-|–|—|~|ate|as|a|to|au|hasta)\s*(\d{1,2})(?:[:h.](\d{2})|h)?',
  );
  static final RegExp _word = RegExp(r'[a-z]+');
  static final RegExp _dayConnector =
      RegExp(r'^\s*(-|–|—|a|as|ate|to|au|al|thru|through)\s*$');

  static String? _hm(String h, String? m) {
    final hour = int.tryParse(h);
    final minute = int.tryParse(m ?? '0');
    if (hour == null || minute == null) return null;
    final hh = hour == 24 ? 0 : hour;
    if (hh > 23 || minute > 59) return null;
    return '${hh.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// Dias citados em [part]; `a`/`to`/`-` entre dois dias = intervalo.
  static Set<int> _days(String part) {
    final days = <int>{};
    if (_allDaysWords.any(part.contains)) {
      return {1, 2, 3, 4, 5, 6, 7};
    }
    int? prev;
    var prevEnd = 0;
    for (final m in _word.allMatches(part)) {
      final w = m.group(0)!;
      if (w.length < 3) continue;
      final d = _dayPrefix[w.substring(0, 3)];
      if (d == null) continue;
      if (prev != null &&
          _dayConnector.hasMatch(part.substring(prevEnd, m.start))) {
        var x = prev;
        while (x != d) {
          days.add(x);
          x = x == 7 ? 1 : x + 1;
        }
      }
      days.add(d);
      prev = d;
      prevEnd = m.end;
    }
    return days;
  }

  /// Nulo = texto que não dá para ler (mostrar o texto, não "fechado").
  static List<PlaceHours>? parseLegacy(String note) {
    final text = _fold(note.trim());
    if (text.isEmpty) return null;
    final lines = text
        .split(RegExp(r'[\n;|]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final result = <PlaceHours>[];
    var understood = false;
    for (final line in lines) {
      final ranges = _range.allMatches(line).toList();
      final dayPart =
          ranges.isEmpty ? line : line.substring(0, ranges.first.start);
      var days = _days(dayPart);
      if (ranges.isEmpty) {
        if (days.isNotEmpty && _closedWords.any(line.contains)) {
          understood = true;
        }
        continue;
      }
      if (days.isEmpty) {
        if (lines.length != 1) continue;
        days = {1, 2, 3, 4, 5, 6, 7};
      }
      for (final r in ranges.take(2)) {
        final o = _hm(r.group(1)!, r.group(2));
        final c = _hm(r.group(3)!, r.group(4));
        if (o == null || c == null || o == c) continue;
        understood = true;
        for (final d in days) {
          result.add(PlaceHours(weekday: d, opens: o, closes: c));
        }
      }
    }
    if (!understood) return null;
    result.sort((a, b) => a.weekday.compareTo(b.weekday));
    return result;
  }

  // ---------- fuso do local ----------

  static String _key(String s) => _fold(s).replaceAll(RegExp(r'[^a-z]'), '');

  static const Map<String, String> _ca = {
    'bc': 'America/Vancouver',
    'britishcolumbia': 'America/Vancouver',
    'ab': 'America/Edmonton',
    'alberta': 'America/Edmonton',
    'sk': 'America/Regina',
    'saskatchewan': 'America/Regina',
    'mb': 'America/Winnipeg',
    'manitoba': 'America/Winnipeg',
    'on': 'America/Toronto',
    'ontario': 'America/Toronto',
    'qc': 'America/Toronto',
    'quebec': 'America/Toronto',
    'nb': 'America/Moncton',
    'newbrunswick': 'America/Moncton',
    'ns': 'America/Halifax',
    'novascotia': 'America/Halifax',
    'pe': 'America/Halifax',
    'princeedwardisland': 'America/Halifax',
    'nl': 'America/St_Johns',
    'newfoundlandandlabrador': 'America/St_Johns',
    'yt': 'America/Whitehorse',
    'yukon': 'America/Whitehorse',
    'nt': 'America/Yellowknife',
    'northwestterritories': 'America/Yellowknife',
    'nu': 'America/Iqaluit',
    'nunavut': 'America/Iqaluit',
  };
  static const Map<String, String> _caCity = {
    'toronto': 'America/Toronto',
    'ottawa': 'America/Toronto',
    'montreal': 'America/Toronto',
    'vancouver': 'America/Vancouver',
    'calgary': 'America/Edmonton',
    'edmonton': 'America/Edmonton',
    'winnipeg': 'America/Winnipeg',
    'halifax': 'America/Halifax',
  };
  static const Map<String, String> _br = {
    'ac': 'America/Rio_Branco',
    'acre': 'America/Rio_Branco',
    'am': 'America/Manaus',
    'amazonas': 'America/Manaus',
    'rr': 'America/Boa_Vista',
    'roraima': 'America/Boa_Vista',
    'ro': 'America/Porto_Velho',
    'rondonia': 'America/Porto_Velho',
    'mt': 'America/Cuiaba',
    'matogrosso': 'America/Cuiaba',
    'ms': 'America/Campo_Grande',
    'matogrossodosul': 'America/Campo_Grande',
    'pa': 'America/Belem',
    'para': 'America/Belem',
    'ap': 'America/Belem',
    'amapa': 'America/Belem',
  };

  /// IANA derivado de país/estado/cidade; nulo = usar o relógio do aparelho.
  static String? zoneFor(String countryCode, String region, String city) {
    final r = _key(region);
    switch (countryCode.trim().toUpperCase()) {
      case 'CA':
        return _ca[r] ?? _caCity[_key(city)] ?? 'America/Toronto';
      case 'BR':
        return _br[r] ?? 'America/Sao_Paulo';
      case 'PT':
        if (r.contains('acores') || r.contains('azores')) {
          return 'Atlantic/Azores';
        }
        if (r.contains('madeira')) return 'Atlantic/Madeira';
        return 'Europe/Lisbon';
    }
    return null;
  }

  /// [instant] no relógio do local. Sem banco tz carregado ou fuso
  /// inválido, usa o horário do aparelho (comportamento anterior).
  static DateTime localTime(DateTime instant, String? zone) {
    if (zone == null || zone.isEmpty) return instant;
    try {
      return tz.TZDateTime.from(instant, tz.getLocation(zone));
    } catch (_) {
      return instant;
    }
  }

  /// Aberto em [local] (já no fuso do local). Faixa que passa da
  /// meia-noite conta no dia em que abre e na madrugada do dia seguinte.
  static bool isOpen(List<PlaceHours> slots, DateTime local) {
    final minute = local.hour * 60 + local.minute;
    final today = local.weekday;
    final yesterday = today == 1 ? 7 : today - 1;
    for (final s in slots) {
      final start = s.opensMinutes;
      final end = s.closesMinutes;
      if (start == end) continue;
      if (s.weekday == today) {
        if (end > start && minute >= start && minute < end) return true;
        if (end < start && minute >= start) return true;
      }
      if (s.weekday == yesterday && end < start && minute < end) return true;
    }
    return false;
  }
}
