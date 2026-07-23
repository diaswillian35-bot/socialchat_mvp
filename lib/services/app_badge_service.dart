import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sincroniza o badge do ícone (iOS) com a contagem real de threads não lidas.
class AppBadgeService {
  AppBadgeService._();

  static const _channel = MethodChannel('remdy/app_badge');
  static int _last = -1;

  static Future<void> setBadge(int count) async {
    if (kIsWeb) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;
    final safe = count < 0 ? 0 : count;
    if (safe == _last) return;
    _last = safe;
    try {
      await _channel.invokeMethod<void>('setBadge', safe);
    } catch (e) {
      debugPrint('AppBadgeService.setBadge failed: $e');
    }
  }
}
