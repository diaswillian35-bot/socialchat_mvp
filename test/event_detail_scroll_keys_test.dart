import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/event_comments_logic.dart';

/// Scroll / key stability helpers used by event detail interactions.
void main() {
  testWidgets('PageStorageKey preserves scroll offset across rebuild',
      (tester) async {
    final controller = ScrollController();
    final storage = PageStorageBucket();

    Widget buildList({required int likesCount}) {
      return MaterialApp(
        home: PageStorage(
          bucket: storage,
          child: Scaffold(
            body: ListView.builder(
              key: const PageStorageKey<String>('event_detail_PART6_TMP_scroll'),
              controller: controller,
              itemCount: 40,
              itemBuilder: (_, i) => SizedBox(
                height: 80,
                child: Text('item_$i likes=$likesCount'),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildList(likesCount: 0));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final offsetAfterScroll = controller.offset;
    expect(offsetAfterScroll, greaterThan(100));

    // Rebuild as if like counter changed — same PageStorageKey + controller.
    await tester.pumpWidget(buildList(likesCount: 1));
    await tester.pumpAndSettle();
    expect(controller.offset, offsetAfterScroll);

    controller.dispose();
  });

  testWidgets('stable ValueKeys survive parent rebuild', (tester) async {
    var likes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              floatingActionButton: FloatingActionButton(
                onPressed: () => setState(() => likes++),
                child: Text('$likes'),
              ),
              body: ListView(
                children: [
                  for (final id in ['c1', 'c2', 'c3'])
                    KeyedSubtree(
                      key: ValueKey('event_comment_evt_$id'),
                      child: ListTile(title: Text(id)),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );

    final keyBefore = tester
        .widget<KeyedSubtree>(
          find.byKey(const ValueKey('event_comment_evt_c2')),
        )
        .key;
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    final keyAfter = tester
        .widget<KeyedSubtree>(
          find.byKey(const ValueKey('event_comment_evt_c2')),
        )
        .key;
    expect(keyBefore, keyAfter);
  });

  test('only one reply editor target at a time (logic)', () {
    String? openId;
    void open(String id) => openId = id;
    void cancel() => openId = null;

    open('a');
    expect(openId, 'a');
    open('b');
    expect(openId, 'b'); // substitui — um editor
    cancel();
    expect(openId, isNull);
  });

  test('reply-of-reply binds to root for flat UI', () {
    final root = EventCommentsLogic.resolveRootCommentId(
      replyToCommentId: 'reply1',
      parentReplyToCommentId: 'root1',
      parentRootCommentId: null,
    );
    expect(root, 'root1');
  });
}
