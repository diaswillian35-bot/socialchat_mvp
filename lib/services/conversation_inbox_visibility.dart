import 'package:cloud_firestore/cloud_firestore.dart';

/// Inbox (aba Mensagens): esconde threads sem preview e threads
/// "apagadas para mim" via [hiddenFor] no documento pai.
///
/// Não mexe em [hiddenFor]/[deletedFor] de mensagens individuais —
/// reaparecer na lista não restaura histórico apagado mensagem a mensagem.
class ConversationInboxVisibility {
  ConversationInboxVisibility._();

  static List<String> hiddenForUids(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  static bool isHiddenForMe(dynamic hiddenFor, String myUid) {
    if (myUid.trim().isEmpty) return true;
    return hiddenForUids(hiddenFor).contains(myUid);
  }

  /// Conversas criadas ao abrir o perfil (lastMessage vazio) ficam só na
  /// bandeira/pessoas, não na aba Mensagens.
  static bool hasListPreview(String? lastMessage) =>
      (lastMessage ?? '').trim().isNotEmpty;

  static bool shouldShowInMessagesTab({
    required Map<String, dynamic> data,
    required String myUid,
  }) {
    if (isHiddenForMe(data['hiddenFor'], myUid)) return false;
    return hasListPreview(data['lastMessage']?.toString());
  }

  /// Após mensagem real enviada ou recebida: tira o marcador de esconder
  /// dos participantes, sem reescrever o array inteiro.
  static FieldValue hiddenForUnhide(Iterable<String> participantUids) {
    final uids = participantUids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    return FieldValue.arrayRemove(uids);
  }

  /// Apply with [DocumentReference.update], never [DocumentReference.set].
  /// `set(merge)` stores `unread.<uid>` as a literal field name. `update`
  /// writes the nested map entry and leaves the other participant alone.
  static Map<String, dynamic> parentSummaryAfterRealMessage({
    required String lastMessage,
    required String myUid,
    String? otherUid,
  }) {
    return {
      'lastMessage': lastMessage,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'unread.$myUid': 0,
      'hiddenFor': hiddenForUnhide([myUid, if (otherUid != null) otherUid]),
    };
  }
}
