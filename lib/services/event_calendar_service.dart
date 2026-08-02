import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adiciona evento ao calendário do aparelho via arquivo `.ics` local.
/// Sem Firebase e sem dados privados.
class EventCalendarService {
  EventCalendarService._();

  static String _prefKey(String eventId) => 'event_calendar_added_$eventId';

  static Future<bool> wasAdded(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(eventId)) == true;
  }

  static Future<void> markAdded(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(eventId), true);
  }

  /// Gera `.ics` temporário e abre o share sheet nativo para o calendário.
  static Future<EventCalendarResult> shareIcs({
    required String eventId,
    required String title,
    required DateTime start,
    DateTime? end,
    required String location,
    required String description,
    required String url,
  }) async {
    if (await wasAdded(eventId)) {
      return EventCalendarResult.alreadyAdded;
    }

    final endAt = end ?? start.add(const Duration(hours: 2));
    final ics = _buildIcs(
      uid: '$eventId@remdy.app',
      title: title,
      start: start,
      end: endAt,
      location: location,
      description: description,
      url: url,
    );

    final dir = await getTemporaryDirectory();
    final safeName = eventId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File('${dir.path}/remdy_event_$safeName.ics');
    await file.writeAsString(ics, flush: true);

    try {
      final shareResult = await Share.shareXFiles(
        [
          XFile(
            file.path,
            mimeType: 'text/calendar',
            name: '$safeName.ics',
          ),
        ],
        subject: title,
      );

      if (shareResult.status == ShareResultStatus.dismissed) {
        return EventCalendarResult.cancelled;
      }
      if (shareResult.status == ShareResultStatus.unavailable) {
        return EventCalendarResult.permissionDenied;
      }

      await markAdded(eventId);
      return EventCalendarResult.shared;
    } catch (_) {
      return EventCalendarResult.failed;
    } finally {
      // Limpeza best-effort.
      Future<void>.delayed(const Duration(minutes: 10), () async {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      });
    }
  }

  static String _buildIcs({
    required String uid,
    required String title,
    required DateTime start,
    required DateTime end,
    required String location,
    required String description,
    required String url,
  }) {
    String esc(String raw) {
      return raw
          .replaceAll('\\', '\\\\')
          .replaceAll(';', '\\;')
          .replaceAll(',', '\\,')
          .replaceAll('\n', '\\n');
    }

    String fmt(DateTime dt) {
      final u = dt.toUtc();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${u.year}${two(u.month)}${two(u.day)}T'
          '${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
    }

    final now = fmt(DateTime.now());
    final buffer = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//Remdy//Event//EN')
      ..writeln('CALSCALE:GREGORIAN')
      ..writeln('METHOD:PUBLISH')
      ..writeln('BEGIN:VEVENT')
      ..writeln('UID:$uid')
      ..writeln('DTSTAMP:$now')
      ..writeln('DTSTART:${fmt(start)}')
      ..writeln('DTEND:${fmt(end)}')
      ..writeln('SUMMARY:${esc(title)}');
    if (location.trim().isNotEmpty) {
      buffer.writeln('LOCATION:${esc(location)}');
    }
    final desc = [
      if (description.trim().isNotEmpty) description.trim(),
      if (url.trim().isNotEmpty) url.trim(),
    ].join('\\n');
    if (desc.isNotEmpty) {
      buffer.writeln('DESCRIPTION:${esc(desc)}');
    }
    if (url.trim().isNotEmpty) {
      buffer.writeln('URL:${esc(url.trim())}');
    }
    buffer
      ..writeln('END:VEVENT')
      ..writeln('END:VCALENDAR');
    return buffer.toString();
  }
}

enum EventCalendarResult {
  shared,
  alreadyAdded,
  cancelled,
  permissionDenied,
  failed,
}
