/// Helpers puros para lista de mensagens estável (sem piscar) e retry.
///
/// Regras:
/// - ID da mensagem é gerado antecipadamente (Firestore doc id).
/// - Pendência local usa o mesmo ID do documento do servidor.
/// - Retry reutiliza o mesmo ID e a mesma chave de bolha.
/// - Pendência some só quando o snapshot já contém esse ID.
/// - Upload concluído é reutilizado se só a gravação falhou.
class ChatMessageListStability {
  ChatMessageListStability._();

  /// Remove da lista pendente os IDs que já existem no servidor.
  static List<T> pruneConfirmedPending<T extends Object>({
    required List<T> pending,
    required String Function(T item) idOf,
    required Set<String> serverIds,
  }) {
    if (pending.isEmpty || serverIds.isEmpty) {
      return List<T>.of(pending);
    }
    return <T>[
      for (final item in pending)
        if (!serverIds.contains(idOf(item))) item,
    ];
  }

  /// IDs pendentes que ainda devem aparecer (não confirmados no servidor).
  static Set<String> visiblePendingIds({
    required Iterable<String> pendingIds,
    required Set<String> serverIds,
  }) {
    return pendingIds
        .where((id) => id.isNotEmpty && !serverIds.contains(id))
        .toSet();
  }

  /// Evita duplicar a mesma mensagem (otimista + confirmada).
  static bool shouldShowPending({
    required String pendingId,
    required Set<String> serverIds,
  }) {
    if (pendingId.isEmpty) return false;
    return !serverIds.contains(pendingId);
  }

  /// Snapshot confirmou exatamente este ID → pode remover a pendência.
  static bool shouldRemovePendingOnSnapshot({
    required String pendingId,
    required Set<String> serverIds,
  }) {
    return pendingId.isNotEmpty && serverIds.contains(pendingId);
  }

  /// Chave estável da bolha (retry deve devolver a mesma string).
  static String bubbleKey(String messageId) => 'msg_$messageId';

  /// Retry só inicia se falhou e não há envio em andamento.
  static bool canStartRetry({
    required bool failed,
    required bool sending,
  }) {
    return failed && !sending;
  }

  /// Dois toques rápidos: o segundo é ignorado enquanto `sending`.
  static bool shouldIgnoreConcurrentSend({required bool sending}) => sending;

  /// Reutilizar URL já enviada ao Storage (evita arquivo duplicado).
  static bool shouldReuseUpload(String? uploadedUrl) {
    return uploadedUrl != null && uploadedUrl.trim().isNotEmpty;
  }

  /// Resolve URL: cache do upload anterior ou null (precisa subir de novo).
  static String? resolveUploadUrl({
    required String? cachedUploadUrl,
  }) {
    if (shouldReuseUpload(cachedUploadUrl)) {
      return cachedUploadUrl!.trim();
    }
    return null;
  }

  /// Mensagem de UI nunca inclui exceção técnica.
  static String userFacingSendFailureLabel(String translated) {
    final t = translated.trim();
    // Guarda: se alguém passar "$e" ou stack, devolve vazio para o caller
    // usar só a chave traduzida — testes cobrem que não concatenamos erros.
    if (t.contains('Exception') ||
        t.contains('Firebase') ||
        t.contains('StackTrace') ||
        RegExp(r'\[.*\]').hasMatch(t) && t.contains('/')) {
      return translated.split(':').first.trim();
    }
    return t;
  }

  /// True se a string parece erro técnico (não deve ir para a UI).
  static bool looksLikeTechnicalError(String message) {
    final m = message.trim();
    if (m.isEmpty) return false;
    if (m.contains('Exception')) return true;
    if (m.contains('FirebaseException')) return true;
    if (m.contains('cloud_firestore')) return true;
    if (m.contains('firebase_storage')) return true;
    if (m.contains('SocketException')) return true;
    if (m.contains('PERMISSION_DENIED')) return true;
    if (RegExp(r'/\S+/\S+').hasMatch(m) && m.contains('Error')) return true;
    return false;
  }

  /// Timestamp de fallback quando `serverTimestamp` ainda não resolveu.
  static DateTime resolveSortTime({
    DateTime? serverCreatedAt,
    DateTime? clientCreatedAt,
    DateTime? pendingCreatedAt,
  }) {
    return serverCreatedAt ??
        clientCreatedAt ??
        pendingCreatedAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
}
