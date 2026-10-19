import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/pages/country_people_page.dart').readAsStringSync();

  test('country page paginates beyond first 40 and search drains pages', () {
    expect(source, contains('static const int _pageSize = 40'));
    expect(source, contains('startAfterDocument(_lastDoc!)'));
    expect(source, contains('while (_hasMore && _lastDoc != null)'));
  });

  test('country page uses live presence and nested accordions without counts',
      () {
    expect(source, contains('PresenceOnlineSetBuilder'));
    expect(source, contains("PageStorageKey('country-state-"));
    expect(source, contains("PageStorageKey('country-city-"));
    expect(source, isNot(contains('people.length}')));
  });

  test('all country sections open by default', () {
    expect(source, contains('bool initiallyExpanded = true'));
    expect(source, contains('people_other_cities_of_state'));
    expect(source, isNot(contains('nearbyCities')));
  });

  test('security and international chat paths remain wired', () {
    expect(source, contains('blockedUids.contains'));
    expect(source, contains("ageVerificationStatus'] != 'verified'"));
    // Opt-in "Mostrar pessoas perto de mim" continua obrigatório.
    expect(source, contains("data['nearbyEnabled'] != true"));
    expect(source, contains('InternationalChatService.canSendMessage'));
    expect(source, contains('BlockService.allowOpenPeer'));
  });
}
