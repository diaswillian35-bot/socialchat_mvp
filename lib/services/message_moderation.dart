/// Leitura do campo `moderation` nas mensagens e nas listas.
/// Não altera layout: só decide qual texto do balão já existente mostrar.
class MessageModeration {
  MessageModeration._();

  static String statusOf(Map<String, dynamic> data) {
    final raw = data['moderation'];
    if (raw is Map) return (raw['status'] ?? '').toString();
    return '';
  }

  static bool hidesImage({
    required String status,
    required bool isMe,
    required String type,
  }) {
    if (type != 'image') return false;
    if (status == 'blocked') return true;
    if (status == 'review' && !isMe) return true;
    return false;
  }

  static bool hidesText({
    required String status,
    required String type,
  }) {
    if (type == 'image' || type == 'audio') return false;
    return status == 'blocked';
  }

  /// Prévia da caixa de entrada quando o servidor marcou o último item.
  static String inboxPreview({
    required Map<String, dynamic> data,
    required String raw,
    required String imageLabel,
    required String textLabel,
  }) {
    if ((data['lastMessageModeration'] ?? '').toString() != 'blocked') {
      return raw;
    }
    final type = (data['lastMessageType'] ?? '').toString();
    if (type == 'image') return imageLabel;
    return textLabel;
  }
}

/// Usuários suspensos ou banidos pela moderação somem das listas,
/// no mesmo ponto em que contas banidas/excluídas já são filtradas.
class ModerationVisibility {
  ModerationVisibility._();

  static bool isHiddenFromLists(Map<String, dynamic>? data) {
    if (data == null) return false;
    final raw = data['moderation'];
    if (raw is! Map) return false;
    final status = (raw['status'] ?? '').toString();
    return status == 'suspended_pending_review' || status == 'banned';
  }
}
