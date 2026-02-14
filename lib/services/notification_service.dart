import 'package:flutter/foundation.dart';
import 'push_service.dart';

/// ✅ NotificationService agora só chama o PushService.
/// Motivo: evitar duplicar listeners e dar bug/piscar.
class NotificationService {
  static Future<void> init() async {
    debugPrint('NotificationService: usando PushService (único)');
    await PushService.init();
  }
}
