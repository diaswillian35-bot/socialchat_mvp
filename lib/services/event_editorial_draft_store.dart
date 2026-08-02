import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/event_editorial_draft.dart';

/// Persistência local do rascunho do wizard por uid.
class EventEditorialDraftStore {
  EventEditorialDraftStore._();

  static String _key(String uid) => 'event_editorial_draft_v1_$uid';

  static Future<void> save(String uid, EventEditorialDraft draft) async {
    final id = uid.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(id), jsonEncode(draft.toJson()));
  }

  static Future<EventEditorialDraft?> load(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(id));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      return EventEditorialDraft.fromJson(Map<String, dynamic>.from(map));
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(id));
  }
}
