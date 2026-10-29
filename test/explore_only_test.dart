import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/explore_only.dart';
import 'package:socialchat_mvp/services/user_location_scope.dart';

void main() {
  test('exploreOnly some das listas de descoberta', () {
    expect(ExploreOnly.isExploreOnlyData({'exploreOnly': true}), isTrue);
    expect(ExploreOnly.isExploreOnlyData({'exploreOnly': false}), isFalse);
    expect(ExploreOnly.isExploreOnlyData(null), isFalse);
    expect(UserLocationScope.isDiscoverableProfile({'exploreOnly': true}), isFalse);
  });

  test('regras bloqueiam conversa nova com quem está em Só explorar', () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules.contains('!peerIsExploreOnly(request.resource.data.participants)'), isTrue);
    final dm = File('functions/send_dm_message_core.js').readAsStringSync();
    expect(dm.contains('explore-only'), isTrue);
    final search = File('functions/user_search.js').readAsStringSync();
    expect(search.contains('userData.exploreOnly === true'), isTrue);
  });

  test('textos do modo nos 5 idiomas', () {
    for (final c in ['pt-BR', 'en', 'es', 'fr']) {
      final s = File('lib/l10n/$c.json').readAsStringSync();
      for (final k in ['explore_only_title', 'explore_only_info', 'explore_only_no_chat', 'admin_mode_title']) {
        expect(s.contains('"$k"'), isTrue, reason: '$c sem $k');
      }
    }
  });
}
