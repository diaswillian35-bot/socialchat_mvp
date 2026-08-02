import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/pages/events_discover_page.dart';
import 'package:socialchat_mvp/pages/events_page_new.dart';

void main() {
  test('EventsDiscoverPage permanece no código para avaliação futura', () {
    expect(const EventsDiscoverPage(), isA<EventsDiscoverPage>());
  });

  test('EventsPage clássica existe', () {
    expect(const EventsPage(), isA<EventsPage>());
  });

  test('MainShell aba Eventos usa EventsPage, não EventsDiscoverPage', () {
    final src = File('lib/pages/main_shell_page.dart').readAsStringSync();
    expect(src.contains("import 'events_page_new.dart';"), isTrue);
    expect(src.contains('const EventsPage()'), isTrue);
    expect(src.contains('EventsDiscoverPage'), isFalse);
    expect(src.contains("import 'events_discover_page.dart';"), isFalse);
  });

  test('EventsPage abre detalhe atual (import EventDetailPage)', () {
    final src = File('lib/pages/events_page_new.dart').readAsStringSync();
    expect(src.contains("import 'event_detail_page.dart';"), isTrue);
    expect(src.contains('EventDetailPage'), isTrue);
  });
}
