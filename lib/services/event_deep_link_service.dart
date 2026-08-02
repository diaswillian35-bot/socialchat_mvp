import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_texts.dart';
import '../pages/event_detail_page.dart';
import 'push_service.dart';

/// Deep links de eventos: `https://remdy.app/e/{eventId}`
/// (também aceita `/events/{eventId}`).
class EventDeepLinkService {
  EventDeepLinkService._();

  static const prefsKey = 'pending_event_id';
  static String? _lastOpenedEventId;
  static DateTime? _lastOpenedAt;

  static String? parseEventId(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.isNotEmpty &&
        host != 'remdy.app' &&
        host != 'www.remdy.app') {
      return null;
    }

    final segments = uri.pathSegments
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.length < 2) return null;

    final root = segments.first.toLowerCase();
    if (root != 'e' && root != 'events' && root != 'event') {
      return null;
    }

    final eventId = segments[1].trim();
    if (eventId.isEmpty || eventId.length > 128) return null;
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(eventId)) return null;
    return eventId;
  }

  static Future<void> savePendingEventId(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, eventId);
  }

  static Future<String?> takePendingEventId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = (prefs.getString(prefsKey) ?? '').trim();
    if (id.isEmpty) return null;
    await prefs.remove(prefsKey);
    return id;
  }

  static bool _isDuplicate(String eventId) {
    final now = DateTime.now();
    if (_lastOpenedEventId == eventId &&
        _lastOpenedAt != null &&
        now.difference(_lastOpenedAt!) < const Duration(seconds: 2)) {
      return true;
    }
    _lastOpenedEventId = eventId;
    _lastOpenedAt = now;
    return false;
  }

  /// Valida acesso e abre [EventDetailPage]. Retorna false se não abriu.
  static Future<bool> openEventById(
    BuildContext context, {
    required String eventId,
    bool replace = false,
  }) async {
    final id = eventId.trim();
    if (id.isEmpty) return false;
    if (_isDuplicate(id)) return false;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      await savePendingEventId(id);
      return false;
    }

    try {
      final doc =
          await FirebaseFirestore.instance.collection('events').doc(id).get();
      if (!context.mounted) return false;

      if (!doc.exists) {
        _showMessage(context, AppTexts.t('event_not_found'));
        return false;
      }

      final data = doc.data() ?? {};
      if (data['deleted'] == true) {
        _showMessage(context, AppTexts.t('event_link_unavailable'));
        return false;
      }

      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      final isActive = data['isActive'] == true;
      final createdBy = (data['createdBy'] ??
              data['organizerId'] ??
              data['ownerId'] ??
              data['userId'] ??
              '')
          .toString()
          .trim();
      final isOwner = createdBy.isNotEmpty && createdBy == uid;

      if (status == 'pending' || status == 'rejected') {
        if (!isOwner) {
          _showMessage(context, AppTexts.t('event_link_unavailable'));
          return false;
        }
      } else if (status == 'cancelled') {
        // Detalhe pode abrir; mensagem discreta.
      } else if (!(status == 'approved' && isActive) && !isOwner) {
        _showMessage(context, AppTexts.t('event_link_unavailable'));
        return false;
      }

      final route = MaterialPageRoute(
        builder: (_) => EventDetailPage(eventId: id),
      );
      if (replace) {
        await Navigator.of(context).pushReplacement(route);
      } else {
        await Navigator.of(context).push(route);
      }

      debugLogOpened(id);
      return true;
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, AppTexts.t('event_open_error'));
      }
      debugLogFailed(id, 'open_error');
      return false;
    }
  }

  static Future<bool> openFromUri(Uri uri, {bool replace = false}) async {
    final eventId = parseEventId(uri);
    if (eventId == null) {
      debugLogFailed('', 'invalid_link');
      return false;
    }

    final nav = PushService.navKey.currentState;
    final ctx = PushService.navKey.currentContext;
    if (nav == null || ctx == null) {
      await savePendingEventId(eventId);
      return false;
    }

    if (FirebaseAuth.instance.currentUser == null) {
      await savePendingEventId(eventId);
      return false;
    }

    return openEventById(ctx, eventId: eventId, replace: replace);
  }

  static Future<void> applyPendingIfAny([BuildContext? fallbackContext]) async {
    final eventId = await takePendingEventId();
    if (eventId == null || eventId.isEmpty) return;

    Future<void> tryOpen() async {
      final ctx =
          PushService.navKey.currentContext ?? fallbackContext;
      if (ctx == null || !ctx.mounted) {
        await savePendingEventId(eventId);
        return;
      }
      await openEventById(ctx, eventId: eventId);
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    await tryOpen();
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static void debugLogOpened(String eventId) {
    debugPrint(
      'event_deep_link_opened eventId=$eventId',
    );
  }

  static void debugLogFailed(String eventId, String reason) {
    debugPrint(
      'event_deep_link_failed eventId=$eventId reason=$reason',
    );
  }
}
