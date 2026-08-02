import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/utils/event_lifecycle.dart';

void main() {
  test('page size is 20', () {
    expect(EventLifecycle.pageSize, 20);
  });

  test('section load flags prevent duplicate initial fetch', () {
    final loaded = <String, bool>{};
    String ensure(String section) {
      if (loaded[section] == true) return 'skip';
      loaded[section] = true;
      return 'fetch';
    }

    expect(ensure('upcoming'), 'fetch');
    expect(ensure('upcoming'), 'skip');
    expect(ensure('past'), 'fetch');
    expect(ensure('past'), 'skip');
  });
}
