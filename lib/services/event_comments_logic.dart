/// Lógica pura de comentários/likes de eventos (testável sem Firebase).
class EventCommentsLogic {
  EventCommentsLogic._();

  static const int maxCommentLength = 1000;

  /// Flatten: respostas de respostas ligam-se ao comentário raiz.
  static String resolveRootCommentId({
    required String? replyToCommentId,
    required String? parentReplyToCommentId,
    required String? parentRootCommentId,
  }) {
    final parentId = (replyToCommentId ?? '').trim();
    if (parentId.isEmpty) return '';
    final parentRoot = (parentRootCommentId ?? '').trim();
    if (parentRoot.isNotEmpty) return parentRoot;
    final parentReply = (parentReplyToCommentId ?? '').trim();
    if (parentReply.isNotEmpty) return parentReply;
    return parentId;
  }

  /// Ordena: principais cronológicos (antigo→novo); replies logo abaixo do pai.
  /// Empate por id estável.
  static List<T> orderThread<T>({
    required List<T> items,
    required String Function(T) idOf,
    required DateTime? Function(T) createdAtOf,
    required String? Function(T) rootOf,
    required String? Function(T) replyToOf,
  }) {
    final byId = <String, T>{for (final i in items) idOf(i): i};
    final roots = <T>[];
    final children = <String, List<T>>{};

    for (final item in items) {
      final root = (rootOf(item) ?? '').trim();
      final replyTo = (replyToOf(item) ?? '').trim();
      final parentKey = root.isNotEmpty
          ? root
          : (replyTo.isNotEmpty ? replyTo : '');
      if (parentKey.isEmpty || !byId.containsKey(parentKey)) {
        roots.add(item);
      } else {
        children.putIfAbsent(parentKey, () => <T>[]).add(item);
      }
    }

    int cmp(T a, T b) {
      final at = createdAtOf(a);
      final bt = createdAtOf(b);
      if (at == null && bt == null) return idOf(a).compareTo(idOf(b));
      if (at == null) return 1; // pending/null vai ao fim do grupo
      if (bt == null) return -1;
      final c = at.compareTo(bt);
      if (c != 0) return c;
      return idOf(a).compareTo(idOf(b));
    }

    roots.sort(cmp);
    for (final list in children.values) {
      list.sort(cmp);
    }

    final out = <T>[];
    for (final root in roots) {
      out.add(root);
      final kids = children[idOf(root)];
      if (kids != null) out.addAll(kids);
    }
    return out;
  }

  static bool canToggleLike({
    required bool isAuthenticated,
    required bool eventDeleted,
    required bool eventCancelled,
    required bool eventActive,
  }) {
    if (!isAuthenticated) return false;
    if (eventDeleted || eventCancelled) return false;
    if (!eventActive) return false;
    return true;
  }

  static int applyLikeDelta({
    required int currentCount,
    required bool currentlyLiked,
    required bool wantLiked,
  }) {
    if (currentlyLiked == wantLiked) return currentCount < 0 ? 0 : currentCount;
    final next = currentlyLiked ? currentCount - 1 : currentCount + 1;
    return next < 0 ? 0 : next;
  }

  /// Double-tap / busy guard.
  static bool shouldIgnoreTap({required bool busy}) => busy;

  static String? validateCommentText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return 'empty';
    if (text.length > maxCommentLength) return 'too_long';
    return null;
  }
}

class EventLikeOptimisticState {
  const EventLikeOptimisticState({
    required this.liked,
    required this.likesCount,
  });

  final bool liked;
  final int likesCount;

  EventLikeOptimisticState toggle() {
    final nextLiked = !liked;
    final nextCount = EventCommentsLogic.applyLikeDelta(
      currentCount: likesCount,
      currentlyLiked: liked,
      wantLiked: nextLiked,
    );
    return EventLikeOptimisticState(liked: nextLiked, likesCount: nextCount);
  }
}
