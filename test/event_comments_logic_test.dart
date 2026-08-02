import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/event_comments_logic.dart';

void main() {
  group('EventCommentsLogic likes', () {
    test('toggle like and unlike deltas', () {
      expect(
        EventCommentsLogic.applyLikeDelta(
          currentCount: 3,
          currentlyLiked: false,
          wantLiked: true,
        ),
        4,
      );
      expect(
        EventCommentsLogic.applyLikeDelta(
          currentCount: 3,
          currentlyLiked: true,
          wantLiked: false,
        ),
        2,
      );
    });

    test('idempotent when state unchanged', () {
      expect(
        EventCommentsLogic.applyLikeDelta(
          currentCount: 5,
          currentlyLiked: true,
          wantLiked: true,
        ),
        5,
      );
    });

    test('never goes below zero', () {
      expect(
        EventCommentsLogic.applyLikeDelta(
          currentCount: 0,
          currentlyLiked: true,
          wantLiked: false,
        ),
        0,
      );
    });

    test('double-tap busy guard', () {
      expect(EventCommentsLogic.shouldIgnoreTap(busy: true), isTrue);
      expect(EventCommentsLogic.shouldIgnoreTap(busy: false), isFalse);
    });

    test('EventLikeOptimisticState toggle', () {
      const s = EventLikeOptimisticState(liked: false, likesCount: 1);
      final n = s.toggle();
      expect(n.liked, isTrue);
      expect(n.likesCount, 2);
      final u = n.toggle();
      expect(u.liked, isFalse);
      expect(u.likesCount, 1);
    });

    test('canToggleLike gates', () {
      expect(
        EventCommentsLogic.canToggleLike(
          isAuthenticated: false,
          eventDeleted: false,
          eventCancelled: false,
          eventActive: true,
        ),
        isFalse,
      );
      expect(
        EventCommentsLogic.canToggleLike(
          isAuthenticated: true,
          eventDeleted: true,
          eventCancelled: false,
          eventActive: true,
        ),
        isFalse,
      );
      expect(
        EventCommentsLogic.canToggleLike(
          isAuthenticated: true,
          eventDeleted: false,
          eventCancelled: true,
          eventActive: true,
        ),
        isFalse,
      );
      expect(
        EventCommentsLogic.canToggleLike(
          isAuthenticated: true,
          eventDeleted: false,
          eventCancelled: false,
          eventActive: true,
        ),
        isTrue,
      );
    });
  });

  group('EventCommentsLogic comments', () {
    test('validate text', () {
      expect(EventCommentsLogic.validateCommentText(''), 'empty');
      expect(EventCommentsLogic.validateCommentText('   '), 'empty');
      expect(EventCommentsLogic.validateCommentText('ok'), isNull);
      expect(
        EventCommentsLogic.validateCommentText('x' * 1001),
        'too_long',
      );
    });

    test('resolveRootCommentId flattens reply-of-reply', () {
      expect(
        EventCommentsLogic.resolveRootCommentId(
          replyToCommentId: 'child',
          parentReplyToCommentId: 'root',
          parentRootCommentId: null,
        ),
        'root',
      );
      expect(
        EventCommentsLogic.resolveRootCommentId(
          replyToCommentId: 'child',
          parentReplyToCommentId: 'mid',
          parentRootCommentId: 'root',
        ),
        'root',
      );
      expect(
        EventCommentsLogic.resolveRootCommentId(
          replyToCommentId: 'root',
          parentReplyToCommentId: null,
          parentRootCommentId: null,
        ),
        'root',
      );
    });

    test('orderThread places replies under parent chronologically', () {
      final items = <_C>[
        _C('r1', DateTime(2024, 1, 2), null, null),
        _C('a', DateTime(2024, 1, 1), null, null),
        _C('a2', DateTime(2024, 1, 1, 0, 2), 'a', 'a'),
        _C('a1', DateTime(2024, 1, 1, 0, 1), 'a', 'a'),
        _C('b', DateTime(2024, 1, 3), null, null),
      ];
      final ordered = EventCommentsLogic.orderThread<_C>(
        items: items,
        idOf: (_C c) => c.id,
        createdAtOf: (_C c) => c.at,
        rootOf: (_C c) => c.root,
        replyToOf: (_C c) => c.replyTo,
      );
      expect(ordered.map((e) => e.id).toList(), ['a', 'a1', 'a2', 'r1', 'b']);
    });

    test('pending null timestamp sorts after dated siblings', () {
      final items = <_C>[
        _C('a', DateTime(2024, 1, 1), null, null),
        _C('p', null, null, null),
        _C('b', DateTime(2024, 1, 2), null, null),
      ];
      final ordered = EventCommentsLogic.orderThread<_C>(
        items: items,
        idOf: (_C c) => c.id,
        createdAtOf: (_C c) => c.at,
        rootOf: (_C c) => c.root,
        replyToOf: (_C c) => c.replyTo,
      );
      expect(ordered.map((e) => e.id).toList(), ['a', 'b', 'p']);
    });

    test('stable id tie-break', () {
      final at = DateTime(2024, 1, 1);
      final items = <_C>[
        _C('b', at, null, null),
        _C('a', at, null, null),
      ];
      final ordered = EventCommentsLogic.orderThread<_C>(
        items: items,
        idOf: (_C c) => c.id,
        createdAtOf: (_C c) => c.at,
        rootOf: (_C c) => c.root,
        replyToOf: (_C c) => c.replyTo,
      );
      expect(ordered.map((e) => e.id).toList(), ['a', 'b']);
    });
  });
}

class _C {
  _C(this.id, this.at, this.root, this.replyTo);
  final String id;
  final DateTime? at;
  final String? root;
  final String? replyTo;
}
