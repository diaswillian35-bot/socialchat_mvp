import 'package:flutter/widgets.dart';

/// Estado central de notificações do Remdy.
///
/// Uma única fonte de verdade para:
/// - ciclo de vida (foreground / background);
/// - conversa privada aberta;
/// - grupo aberto;
/// - evento aberto.
///
/// Regras:
/// - Em foreground: nunca criar notificação visual/local (banner/som/vibração).
/// - Com chat/grupo/evento aberto correspondente: também não notificar visualmente.
/// - Em background/terminated: o SO exibe o push FCM (não duplicar com local).
class AppNotificationState with WidgetsBindingObserver {
  AppNotificationState._();

  static final AppNotificationState instance = AppNotificationState._();

  bool _bound = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  String? _activeConversationId;
  String? _activeGroupId;
  String? _activeEventId;

  bool get isForeground =>
      _lifecycle == AppLifecycleState.resumed ||
      _lifecycle == AppLifecycleState.inactive;

  bool get isBackground => !isForeground;

  String? get activeConversationId => _activeConversationId;
  String? get activeGroupId => _activeGroupId;
  String? get activeEventId => _activeEventId;

  /// Liga o observer de ciclo de vida (chamar 1x no boot do PushService).
  void bind() {
    if (_bound) return;
    WidgetsBinding.instance.addObserver(this);
    _bound = true;
    _lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  }

  void unbind() {
    if (!_bound) return;
    WidgetsBinding.instance.removeObserver(this);
    _bound = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }

  /// Para testes: força o ciclo de vida sem o binding do Flutter.
  @visibleForTesting
  void debugSetLifecycle(AppLifecycleState state) {
    _lifecycle = state;
  }

  @visibleForTesting
  void debugReset() {
    _lifecycle = AppLifecycleState.resumed;
    _activeConversationId = null;
    _activeGroupId = null;
    _activeEventId = null;
  }

  void enterPrivateChat(String conversationId) {
    final id = conversationId.trim();
    if (id.isEmpty) return;
    _activeConversationId = id;
    _activeGroupId = null;
  }

  void enterGroupChat(String groupId) {
    final id = groupId.trim();
    if (id.isEmpty) return;
    _activeGroupId = id;
    _activeConversationId = null;
  }

  void enterEvent(String eventId) {
    final id = eventId.trim();
    if (id.isEmpty) return;
    _activeEventId = id;
  }

  void leavePrivateChat(String conversationId) {
    if (_activeConversationId == conversationId.trim()) {
      _activeConversationId = null;
    }
  }

  void leaveGroupChat(String groupId) {
    if (_activeGroupId == groupId.trim()) {
      _activeGroupId = null;
    }
  }

  void leaveEvent(String eventId) {
    if (_activeEventId == eventId.trim()) {
      _activeEventId = null;
    }
  }

  void clearActiveSurfaces() {
    _activeConversationId = null;
    _activeGroupId = null;
    _activeEventId = null;
  }

  /// Extrai IDs relevantes do payload FCM/data.
  static NotificationTarget targetFromData(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().trim().toLowerCase();
    final conversationId = (data['conversationId'] ?? '').toString().trim();
    final groupId = (data['groupId'] ?? '').toString().trim();
    final eventId = (data['eventId'] ?? '').toString().trim();

    return NotificationTarget(
      type: type,
      conversationId: conversationId.isEmpty ? null : conversationId,
      groupId: groupId.isEmpty ? null : groupId,
      eventId: eventId.isEmpty ? null : eventId,
    );
  }

  /// True se a notificação pertence à superfície atualmente aberta.
  bool isForActiveSurface(NotificationTarget target) {
    if (_activeConversationId != null &&
        target.conversationId == _activeConversationId) {
      return true;
    }
    if (_activeGroupId != null && target.groupId == _activeGroupId) {
      return true;
    }
    if (_activeEventId != null && target.eventId == _activeEventId) {
      return true;
    }
    return false;
  }

  /// Mensagem na conversa/grupo aberto: não deve aumentar unread localmente.
  bool shouldSkipUnreadIncrement(Map<String, dynamic> data) {
    return isForActiveSurface(targetFromData(data));
  }

  /// Deve criar notificação **local** a partir de `onMessage`?
  ///
  /// Sempre `false`:
  /// - Em foreground o Remdy não deve exibir banner/som/vibração;
  /// - Em background/terminated o SO já mostra o payload FCM `notification`.
  /// Criar local aqui causaria o bug atual (push em primeiro plano) ou duplicata.
  bool shouldShowLocalNotification(Map<String, dynamic> data) {
    // Mantém data no signature para testes e futuras regras por tipo.
    if (isForeground) return false;
    if (isForActiveSurface(targetFromData(data))) return false;
    return false;
  }

  /// Alias: em foreground (e em geral no onMessage) sempre suprime visual local.
  bool shouldSuppressVisualNotification(Map<String, dynamic> data) {
    return !shouldShowLocalNotification(data);
  }

  /// Compatível com a API pedida nos testes.
  bool shouldShowVisualNotification(Map<String, dynamic> data) =>
      shouldShowLocalNotification(data);
}

class NotificationTarget {
  final String type;
  final String? conversationId;
  final String? groupId;
  final String? eventId;

  const NotificationTarget({
    required this.type,
    this.conversationId,
    this.groupId,
    this.eventId,
  });

  bool get isPrivateChat =>
      type == 'chat' || type == 'private' || conversationId != null;

  bool get isGroup => type.startsWith('group') || groupId != null;

  bool get isEvent => type.startsWith('event') || eventId != null;
}
