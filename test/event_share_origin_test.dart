import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/event_share_image_service.dart';

void main() {
  test('button rect inside the view is the popover anchor', () {
    const view = Size(1180, 820);
    const button = Rect.fromLTWH(900, 40, 44, 44);
    expect(
      EventShareOrigin.resolve(button: button, viewSize: view),
      button,
    );
  });

  test('off-screen or empty button falls back to a point inside the view', () {
    const view = Size(390, 844);
    final anchor = EventShareOrigin.resolve(
      button: const Rect.fromLTWH(-40, -40, 10, 10),
      viewSize: view,
    );
    expect(anchor, isNotNull);
    expect(anchor!.width, greaterThan(0));
    expect(anchor.height, greaterThan(0));
    expect(anchor.left, greaterThanOrEqualTo(0));
    expect(anchor.top, greaterThanOrEqualTo(0));
    expect(anchor.right, lessThanOrEqualTo(view.width));
    expect(anchor.bottom, lessThanOrEqualTo(view.height));
  });

  test('missing view and missing button do not invent an anchor', () {
    expect(EventShareOrigin.resolve(button: null, viewSize: null), isNull);
    expect(
      EventShareOrigin.resolve(button: Rect.zero, viewSize: Size.zero),
      isNull,
    );
    expect(
      EventShareOrigin.resolve(
        button: const Rect.fromLTWH(double.nan, 0, 10, 10),
        viewSize: null,
      ),
      isNull,
    );
  });

  testWidgets('share chip context resolves to the button', (tester) async {
    late BuildContext shareContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Builder(
              builder: (context) {
                shareContext = context;
                return const SizedBox(width: 34, height: 34);
              },
            ),
          ),
        ),
      ),
    );
    final origin = EventShareOrigin.fromContext(shareContext);
    expect(origin, isNotNull);
    expect(origin!.width, 34);
    expect(origin.height, 34);
  });

  test('list and detail share pass the same public link and an origin', () {
    final list = File('lib/pages/events_page_new.dart').readAsStringSync();
    final detail = File('lib/pages/event_detail_page.dart').readAsStringSync();
    expect(list.contains('https://remdy.app/e/\$eventId'), isTrue);
    expect(detail.contains('https://remdy.app/e/\${event.id}'), isTrue);
    expect(list.contains('sharePositionOrigin:'), isTrue);
    expect(detail.contains('sharePositionOrigin: shareOrigin'), isTrue);
    expect(list.contains('EventShareOrigin.fromContext'), isTrue);
  });
}
